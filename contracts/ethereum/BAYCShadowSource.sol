// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title BAYCShadowSource
 * @author ApeChain Core Contributors
 * @notice Source contract on Ethereum Mainnet that tracks BAYC ownership and syncs to ApeChain
 * @dev Emits LayerZero messages when BAYC tokens are transferred, triggering shadow updates on ApeChain
 * 
 * This contract:
 * - Watches for BAYC ownership changes
 * - Sends mint/transfer/burn messages to ShadowApe on ApeChain via LayerZero v2
 * - Allows batch syncing and manual triggers
 * - Uses gas-efficient message packing
 */
contract BAYCShadowSource is Ownable, ReentrancyGuard, OApp {
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidTokenId();
    error NotBAYCOwner();
    error InsufficientFee();
    error InvalidApeChainEndpoint();
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OwnershipProofSent(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        SyncAction action,
        bytes32 guid
    );
    
    event BatchSyncCompleted(uint256[] tokenIds, uint256 totalFee);
    
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum SyncAction {
        MINT,      // New shadow minted
        TRANSFER,  // Ownership changed
        BURN       // Shadow burned
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice BAYC contract address on Ethereum Mainnet
    address public constant BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    
    /// @notice ApeChain endpoint ID for LayerZero v2
    uint32 public constant APECHAIN_EID = 30151;
    
    /// @notice Default gas limit for receiving on destination
    uint128 public dstGasLimit = 200_000;
    
    /// @notice Tracking last synced owner for each token ID
    mapping(uint256 => address) public lastSyncedOwner;
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize BAYC Shadow Source contract
     * @param _lzEndpoint LayerZero v2 endpoint address on Ethereum Mainnet
     * @param _initialOwner Contract owner address
     */
    constructor(
        address _lzEndpoint,
        address _initialOwner
    ) 
        Ownable(_initialOwner)
        OApp(_lzEndpoint, _initialOwner)
    {
        // Constructor initialization
    }
    
    /*//////////////////////////////////////////////////////////////
                        SYNC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Sync a single BAYC token's ownership to ApeChain
     * @dev Checks current BAYC owner and sends appropriate message
     * @param tokenId BAYC token ID to sync
     * @param refundAddress Address to refund excess gas fees
     */
    function syncBAYC(uint256 tokenId, address refundAddress) external payable nonReentrant {
        if (tokenId >= 10000) revert InvalidTokenId(); // BAYC has 10k tokens
        
        // Get current owner from BAYC contract
        address currentOwner = IERC721(BAYC).ownerOf(tokenId);
        address previousOwner = lastSyncedOwner[tokenId];
        
        SyncAction action;
        
        if (previousOwner == address(0)) {
            // First sync - mint shadow
            action = SyncAction.MINT;
        } else if (currentOwner != previousOwner) {
            // Owner changed - transfer shadow
            action = SyncAction.TRANSFER;
        } else {
            // No change needed
            return;
        }
        
        // Send message to ApeChain
        bytes32 guid = _sendOwnershipProof(tokenId, previousOwner, currentOwner, action, refundAddress);
        
        // Update tracking
        lastSyncedOwner[tokenId] = currentOwner;
        
        emit OwnershipProofSent(tokenId, previousOwner, currentOwner, action, guid);
    }
    
    /**
     * @notice Sync multiple BAYC tokens in batch
     * @param tokenIds Array of token IDs to sync
     * @param refundAddress Address to refund excess gas fees
     */
    function batchSyncBAYC(
        uint256[] calldata tokenIds,
        address refundAddress
    ) external payable nonReentrant {
        uint256 totalFee = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= 10000) revert InvalidTokenId();
            
            // Get current owner
            address currentOwner = IERC721(BAYC).ownerOf(tokenId);
            address previousOwner = lastSyncedOwner[tokenId];
            
            SyncAction action;
            
            if (previousOwner == address(0)) {
                action = SyncAction.MINT;
            } else if (currentOwner != previousOwner) {
                action = SyncAction.TRANSFER;
            } else {
                continue; // Skip if no change
            }
            
            // Send message
            bytes32 guid = _sendOwnershipProof(tokenId, previousOwner, currentOwner, action, refundAddress);
            
            // Update tracking
            lastSyncedOwner[tokenId] = currentOwner;
            
            emit OwnershipProofSent(tokenId, previousOwner, currentOwner, action, guid);
        }
        
        emit BatchSyncCompleted(tokenIds, msg.value);
    }
    
    /**
     * @notice Report that a BAYC token was burned or is no longer valid
     * @param tokenId Token ID to burn shadow for
     * @param refundAddress Address to refund excess gas fees
     */
    function reportBAYCBurn(
        uint256 tokenId,
        address refundAddress
    ) external payable onlyOwner nonReentrant {
        address previousOwner = lastSyncedOwner[tokenId];
        
        // Send burn message
        bytes32 guid = _sendOwnershipProof(
            tokenId,
            previousOwner,
            address(0),
            SyncAction.BURN,
            refundAddress
        );
        
        // Clear tracking
        delete lastSyncedOwner[tokenId];
        
        emit OwnershipProofSent(tokenId, previousOwner, address(0), SyncAction.BURN, guid);
    }
    
    /*//////////////////////////////////////////////////////////////
                    LAYERZERO MESSAGE SENDING
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Internal function to send ownership proof via LayerZero
     * @param tokenId BAYC token ID
     * @param previousOwner Previous owner address
     * @param currentOwner Current owner address
     * @param action Sync action type
     * @param refundAddress Refund address for excess fees
     * @return guid Message GUID
     */
    function _sendOwnershipProof(
        uint256 tokenId,
        address previousOwner,
        address currentOwner,
        SyncAction action,
        address refundAddress
    ) internal returns (bytes32 guid) {
        // Encode message payload
        bytes memory payload = abi.encode(
            uint8(action),
            tokenId,
            currentOwner,
            previousOwner
        );
        
        // Build message options with gas limit
        bytes memory options = abi.encodePacked(
            uint16(1), // option type
            uint128(dstGasLimit)
        );
        
        // Quote the fee
        MessagingFee memory fee = _quote(APECHAIN_EID, payload, options, false);
        
        if (msg.value < fee.nativeFee) revert InsufficientFee();
        
        // Send message
        MessagingReceipt memory receipt = _lz_send(
            APECHAIN_EID,
            payload,
            options,
            MessagingFee(msg.value, 0),
            refundAddress
        );
        
        return receipt.guid;
    }
    
    /*//////////////////////////////////////////////////////////////
                        QUOTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Quote the gas fee for syncing a single token
     * @param tokenId Token ID to quote for
     * @return fee MessagingFee struct
     */
    function quoteSyncFee(uint256 tokenId) external view returns (MessagingFee memory fee) {
        // Build sample payload
        bytes memory payload = abi.encode(
            uint8(SyncAction.MINT),
            tokenId,
            address(0),
            address(0)
        );
        
        bytes memory options = abi.encodePacked(
            uint16(1),
            uint128(dstGasLimit)
        );
        
        return _quote(APECHAIN_EID, payload, options, false);
    }
    
    /**
     * @notice Quote the total gas fee for batch sync
     * @param count Number of tokens to sync
     * @return totalFee Total estimated fee
     */
    function quoteBatchSyncFee(uint256 count) external view returns (uint256 totalFee) {
        MessagingFee memory singleFee = this.quoteSyncFee(0);
        return singleFee.nativeFee * count;
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update destination gas limit
     * @param newGasLimit New gas limit
     */
    function setDstGasLimit(uint128 newGasLimit) external onlyOwner {
        dstGasLimit = newGasLimit;
    }
    
    /**
     * @notice Withdraw stuck ETH (for failed refunds)
     */
    function withdrawETH() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }
    
    /**
     * @notice Required override - this contract doesn't receive messages
     */
    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal pure override {
        revert("Source contract does not receive messages");
    }
}

/**
 * @notice Minimal IERC721 interface for BAYC interaction
 */
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

