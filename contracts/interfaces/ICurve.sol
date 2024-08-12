// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICurve {
    function checkCompatability(uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (bool);

    function fPrimeX(uint256 x, uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (uint256);

    function fX(uint256 x, uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (uint256);

    function fY(uint256 y, uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (uint256);

    function evaluateDx(uint256 x1, uint256 x2, uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (uint256);

    function evaluateDy(uint256 y1, uint256 y2, uint256 yMin, uint256 yMax, uint256 xMax, uint256 xTotal) external pure returns (uint256);

    error ICurve__InvalidInput();
}