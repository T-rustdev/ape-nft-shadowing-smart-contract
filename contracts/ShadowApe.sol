// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title ShadowApe
 * @author ApeChain Core Contributors
 * @notice Soulbound shadow NFT system that mirrors BAYC ownership from Ethereum Mainnet to ApeChain
 * @dev Uses LayerZero v2 for automatic cross-chain synchronization
 * 
 * Features:
 * - Automatic minting/burning based on Ethereum BAYC ownership
 * - Soulbound by default (non-transferable unless unlocked)
 * - Single-wallet delegation for staking/gaming use cases
 * - Non-blocking message delivery with retry support
 * - Gas-optimized for ApeChain (Arbitrum Orbit)
 */
contract ShadowApe is ERC721Enumerable, Ownable, ReentrancyGuard, OApp {
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error ShadowIsLocked();
    error NotShadowOwner();
    error AlreadyUnlocked();
    error InvalidDelegate();
    error NotAuthorized();
    error ShadowDoesNotExist();
    error InvalidSourceChain();
    error PayloadDecodeFailed();
    error Paused();
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event ShadowMinted(uint256 indexed tokenId, address indexed owner, uint256 timestamp);
    event ShadowBurned(uint256 indexed tokenId, address indexed previousOwner, uint256 timestamp);
    event ShadowDelegated(uint256 indexed tokenId, address indexed owner, address indexed delegate);
    event DelegationRevoked(uint256 indexed tokenId, address indexed owner, address indexed previousDelegate);
    event ShadowUnlocked(uint256 indexed tokenId, address indexed owner, uint256 timestamp);
    event ShadowSynced(uint256 indexed tokenId, address indexed newOwner, SyncAction action);
    event IncomingMessagesPaused(bool paused);
    event BaseURIUpdated(string newBaseURI);
    
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum SyncAction {
        MINT,      // New shadow minted
        TRANSFER,  // Ownership changed
        BURN       // Shadow burned (BAYC no longer owned)
    }
    
    struct ShadowData {
        bool unlocked;           // Whether shadow is transferable
        address delegate;        // Current delegate (0x0 if none)
        uint40 mintedAt;        // Timestamp when shadow was minted
        uint40 lastSyncedAt;    // Last sync timestamp
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Base URI for token metadata (IPFS/Arweave)
    string private _baseTokenURI;
    
    /// @notice Mapping from token ID to shadow data
    mapping(uint256 => ShadowData) public shadows;
    
    /// @notice Mapping from token ID to original shadow owner (for unlock permission)
    mapping(uint256 => address) public originalOwner;
    
    /// @notice Emergency pause for incoming LayerZero messages
    bool public paused;
    
    /// @notice Ethereum Mainnet endpoint ID for LayerZero v2
    uint32 public constant ETH_MAINNET_EID = 30101; // LayerZero v2 Ethereum endpoint ID
    
    /// @notice ApeChain endpoint ID for LayerZero v2
    uint32 public constant APECHAIN_EID = 30151; // ApeChain endpoint ID
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize ShadowApe contract
     * @param _lzEndpoint LayerZero v2 endpoint address on ApeChain
     * @param _initialOwner Contract owner address
     * @param _initialBaseURI Initial base URI for metadata
     */
    constructor(
        address _lzEndpoint,
        address _initialOwner,
        string memory _initialBaseURI
    ) 
        ERC721("ShadowApe", "sAPE")
        Ownable(_initialOwner)
        OApp(_lzEndpoint, _initialOwner)
    {
        _baseTokenURI = _initialBaseURI;
    }
    
    /*//////////////////////////////////////////////////////////////
                        LAYERZERO V2 INTEGRATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Handle incoming LayerZero messages from Ethereum
     * @dev Automatically mints/burns/transfers shadows based on BAYC ownership changes
     * @param _origin Origin information including source endpoint ID
     * @param _guid Global unique identifier for the message
     * @param _message Encoded message payload
     * @param _executor Executor address
     * @param _extraData Additional data
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Check if paused
        if (paused) revert Paused();
        
        // Verify message is from trusted Ethereum source
        if (_origin.srcEid != ETH_MAINNET_EID) revert InvalidSourceChain();
        
        // Decode payload: (uint8 action, uint256 tokenId, address currentOwner, address previousOwner)
        (uint8 actionType, uint256 tokenId, address currentOwner, address previousOwner) = 
            abi.decode(_message, (uint8, uint256, address, address));
        
        SyncAction action = SyncAction(actionType);
        
        if (action == SyncAction.MINT) {
            _handleMint(tokenId, currentOwner);
        } else if (action == SyncAction.TRANSFER) {
            _handleTransfer(tokenId, previousOwner, currentOwner);
        } else if (action == SyncAction.BURN) {
            _handleBurn(tokenId, previousOwner);
        } else {
            revert PayloadDecodeFailed();
        }
        
        emit ShadowSynced(tokenId, currentOwner, action);
    }
    
    /**
     * @notice Handle shadow minting from LayerZero message
     * @param tokenId BAYC token ID
     * @param owner Current owner on Ethereum
     */
    function _handleMint(uint256 tokenId, address owner) private {
        // Only mint if doesn't exist
        if (_ownerOf(tokenId) != address(0)) {
            // Already exists, treat as transfer
            _handleTransfer(tokenId, _ownerOf(tokenId), owner);
            return;
        }
        
        _safeMint(owner, tokenId);
        
        shadows[tokenId] = ShadowData({
            unlocked: false,
            delegate: address(0),
            mintedAt: uint40(block.timestamp),
            lastSyncedAt: uint40(block.timestamp)
        });
        
        originalOwner[tokenId] = owner;
        
        emit ShadowMinted(tokenId, owner, block.timestamp);
    }
    
    /**
     * @notice Handle shadow transfer from LayerZero message
     * @param tokenId BAYC token ID
     * @param from Previous owner
     * @param to New owner
     */
    function _handleTransfer(uint256 tokenId, address from, address to) private {
        address currentOwner = _ownerOf(tokenId);
        
        if (currentOwner == address(0)) {
            // Shadow doesn't exist, mint it
            _handleMint(tokenId, to);
            return;
        }
        
        // Force transfer even if locked (cross-chain sync takes precedence)
        _transfer(from, to, tokenId);
        
        // Clear delegation on ownership change
        if (shadows[tokenId].delegate != address(0)) {
            address previousDelegate = shadows[tokenId].delegate;
            shadows[tokenId].delegate = address(0);
            emit DelegationRevoked(tokenId, to, previousDelegate);
        }
        
        shadows[tokenId].lastSyncedAt = uint40(block.timestamp);
    }
    
    /**
     * @notice Handle shadow burning from LayerZero message
     * @param tokenId BAYC token ID
     * @param previousOwner Previous owner on Ethereum
     */
    function _handleBurn(uint256 tokenId, address previousOwner) private {
        if (_ownerOf(tokenId) == address(0)) return; // Already burned or never existed
        
        address currentOwner = _ownerOf(tokenId);
        _burn(tokenId);
        
        // Clear shadow data
        delete shadows[tokenId];
        delete originalOwner[tokenId];
        
        emit ShadowBurned(tokenId, currentOwner, block.timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                        DELEGATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Delegate control of a shadow to another wallet
     * @dev Allows staking contracts or games to use the shadow while owner retains ownership
     * @param tokenId Token ID to delegate
     * @param delegate Address to delegate to (use address(0) to revoke)
     */
    function delegateShadow(uint256 tokenId, address delegate) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotShadowOwner();
        
        address previousDelegate = shadows[tokenId].delegate;
        shadows[tokenId].delegate = delegate;
        
        if (delegate == address(0)) {
            emit DelegationRevoked(tokenId, msg.sender, previousDelegate);
        } else {
            emit ShadowDelegated(tokenId, msg.sender, delegate);
        }
    }
    
    /**
     * @notice Revoke delegation for a shadow
     * @param tokenId Token ID to revoke delegation for
     */
    function revokeDelegation(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotShadowOwner();
        
        address previousDelegate = shadows[tokenId].delegate;
        if (previousDelegate == address(0)) return; // No active delegation
        
        shadows[tokenId].delegate = address(0);
        emit DelegationRevoked(tokenId, msg.sender, previousDelegate);
    }
    
    /*//////////////////////////////////////////////////////////////
                        UNLOCK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Permanently unlock a shadow to make it fully transferable
     * @dev Only the original shadow owner can unlock. This is irreversible!
     * @param tokenId Token ID to unlock
     */
    function unlockShadow(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotShadowOwner();
        if (shadows[tokenId].unlocked) revert AlreadyUnlocked();
        
        // Must be original owner to unlock
        if (originalOwner[tokenId] != msg.sender) revert NotAuthorized();
        
        shadows[tokenId].unlocked = true;
        emit ShadowUnlocked(tokenId, msg.sender, block.timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                    TRANSFER OVERRIDE (SOULBOUND)
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Override transfer to enforce soulbound behavior
     * @dev Reverts if shadow is locked, allows if unlocked
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == address(0))
        if (from == address(0)) {
            return super._update(to, tokenId, auth);
        }
        
        // Allow burning (to == address(0))
        if (to == address(0)) {
            return super._update(to, tokenId, auth);
        }
        
        // Check if shadow is unlocked
        if (!shadows[tokenId].unlocked) {
            // Only allow internal transfers (from LayerZero sync)
            if (auth != address(this)) {
                revert ShadowIsLocked();
            }
        }
        
        return super._update(to, tokenId, auth);
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get the current delegate for a shadow
     * @param tokenId Token ID to query
     * @return Address of current delegate (address(0) if none)
     */
    function getShadowDelegate(uint256 tokenId) external view returns (address) {
        if (_ownerOf(tokenId) == address(0)) revert ShadowDoesNotExist();
        return shadows[tokenId].delegate;
    }
    
    /**
     * @notice Check if a shadow is unlocked (transferable)
     * @param tokenId Token ID to query
     * @return True if unlocked, false if soulbound
     */
    function isShadowUnlocked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert ShadowDoesNotExist();
        return shadows[tokenId].unlocked;
    }
    
    /**
     * @notice Check if a shadow exists
     * @param tokenId Token ID to query
     * @return True if shadow exists
     */
    function shadowExists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @notice Get complete shadow information
     * @param tokenId Token ID to query
     * @return owner Current owner
     * @return delegate Current delegate
     * @return unlocked Whether shadow is transferable
     * @return mintedAt Mint timestamp
     * @return lastSyncedAt Last sync timestamp
     */
    function getShadowInfo(uint256 tokenId) external view returns (
        address owner,
        address delegate,
        bool unlocked,
        uint40 mintedAt,
        uint40 lastSyncedAt
    ) {
        if (_ownerOf(tokenId) == address(0)) revert ShadowDoesNotExist();
        
        ShadowData memory data = shadows[tokenId];
        return (
            ownerOf(tokenId),
            data.delegate,
            data.unlocked,
            data.mintedAt,
            data.lastSyncedAt
        );
    }
    
    /**
     * @notice Get all shadow token IDs owned by an address
     * @param owner Address to query
     * @return Array of token IDs
     */
    function getShadowsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }
    
    /*//////////////////////////////////////////////////////////////
                        METADATA FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get base URI for token metadata
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    
    /**
     * @notice Update base URI (owner only)
     * @param newBaseURI New base URI
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emergency pause for incoming LayerZero messages
     * @param _paused True to pause, false to unpause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit IncomingMessagesPaused(_paused);
    }
    
    /**
     * @notice Emergency function to mint shadow (only if LayerZero fails)
     * @dev Should rarely be used - LayerZero handles automatic minting
     * @param tokenId Token ID to mint
     * @param to Address to mint to
     */
    function emergencyMint(uint256 tokenId, address to) external onlyOwner {
        require(_ownerOf(tokenId) == address(0), "Shadow already exists");
        _handleMint(tokenId, to);
    }
    
    /**
     * @notice Emergency function to burn shadow
     * @param tokenId Token ID to burn
     */
    function emergencyBurn(uint256 tokenId) external onlyOwner {
        address currentOwner = ownerOf(tokenId);
        _handleBurn(tokenId, currentOwner);
    }
    
    /*//////////////////////////////////////////////////////////////
                    LAYERZERO V2 CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Quote gas fee for LayerZero message
     * @param _dstEid Destination endpoint ID
     * @param _message Message payload
     * @param _options Message options
     * @param _payInLzToken Whether to pay in LZ token
     * @return fee MessagingFee struct with native and lzToken fees
     */
    function quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        return _quote(_dstEid, _message, _options, _payInLzToken);
    }
}

