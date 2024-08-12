// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface ITreasury {
    function receiveAirdrop(address token, uint256 amount) external;
}