// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { INonfungiblePositionManager } from "./interfaces/INonfungiblePositionManager.sol";

/**
 * @title   LP Holder
 * @notice  Permanently locks and collects fees from UniV3 LP positions
 */
contract LpHolder is ERC721Holder, Ownable {
    ////////////////////////////////////////////////////////////////////////////////
    // CONSTANTS AND IMMUTABLES
    ////////////////////////////////////////////////////////////////////////////////

    INonfungiblePositionManager public immutable UNISWAP_V3_NFT_MANAGER;

    ////////////////////////////////////////////////////////////////////////////////
    // STATE
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Receives fees collected from UniV3 LP positions
    address public feeReceiver;

    ////////////////////////////////////////////////////////////////////////////////
    // CONSTRUCTION AND INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    constructor(address _nftManager, address _feeReceiver) Ownable(msg.sender) {
        if (_nftManager == address(0) || _feeReceiver == address(0)) revert LpHolder__ZeroAddress();
        UNISWAP_V3_NFT_MANAGER = INonfungiblePositionManager(_nftManager);
        feeReceiver = _feeReceiver;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // FEE MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Collect fees from UniV3 LP positions
     * @param   tokenIds    Array of token IDs to collect fees from
     */
    function collectFees(uint256[] calldata tokenIds) external {
        if (tokenIds.length == 0) revert LpHolder__ZeroLength();

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: 0,
            recipient: feeReceiver,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        for (uint256 i; i < tokenIds.length; ) {
            params.tokenId = tokenIds[i];
            UNISWAP_V3_NFT_MANAGER.collect(params);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  Sweep tokens from the contract
     * @param   token   Token to sweep
     */
    function sweep(address token) external onlyOwner {
        IERC20(token).transfer(feeReceiver, IERC20(token).balanceOf(address(this)));
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ADMINISTRATION
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Set the fee receiver
     * @param   _feeReceiver    New fee receiver
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert LpHolder__ZeroAddress();
        emit FeeReceiverSet(_feeReceiver, feeReceiver);
        feeReceiver = _feeReceiver;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////////

    event FeeReceiverSet(address newFeeReceiver, address oldFeeReceiver);

    ////////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////////

    error LpHolder__ZeroAddress();
    error LpHolder__ZeroLength();
}