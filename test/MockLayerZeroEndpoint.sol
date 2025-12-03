// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MockLayerZeroEndpoint
 * @notice Mock LayerZero endpoint for testing
 */
contract MockLayerZeroEndpoint {
    event PacketSent(bytes payload, uint32 dstEid);

    function send(
        uint32 _dstEid,
        bytes calldata _message,
        bytes calldata _options,
        address _refundAddress
    ) external payable returns (bytes32) {
        emit PacketSent(_message, _dstEid);
        return keccak256(abi.encodePacked(_dstEid, _message));
    }

    function quote(
        uint32,
        bytes calldata,
        bytes calldata,
        bool
    ) external pure returns (uint256 nativeFee, uint256 lzTokenFee) {
        return (0.001 ether, 0);
    }
}

