// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// @dev The bonding curve for buying and selling tokens before launched on DEX

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ICurve } from "../interfaces/ICurve.sol";
import "hardhat/console.sol";

/**
 * --------------------------------------------------------------------------------
 *
 * @title   CP(Constant Product) Bonding Curve
 * @notice  Calculate bonding curve token prices via a constant product price curve
 *
 * ----------------------------------------------------------------------------
 * @dev This contract uses the cost function:
 *      y = k / (q*xTotal - x)
 *      ( y * (q* xTotal - x) = k )
 *      Where:
 *          y = wei of ETH
 *          x = wei of paired token
 *          k = (xTotal - xMax)^2 * yMax / 1e18
 *          Where:
 *              yMax = the maximum price of the paired token
 *              yMin = the minimum price of the paired token
 *              xMax = the maturation point of the curve (token target)
 *              xTotal = the total supply of the paired token
 *              k = the liquidity constant
 *              q = tuning constant
 *
 *          Since yMin is unused in this curve, it is repurposed to define q, such that q = yMax/yMin.
 *          If q != 1, yMax will not have a direct relation to the end price, and a value of yMax
 *          which results in the desired end price must be solved for offchain.
 *
 *      This approach mimics the behavior of a UniswapV2 constant-product AMM with liquidity k.
 *
 *      The price function can be obtained by taking the derivative of this curve, resulting in:
 *      dy/dx = k / (q*xTotal - x)^2
 *      Where:
 *          dy/dx = wei of eth per 1e18 wei of the paired token
 *          x = wei of paired token
 *
 *      Input limitations:
 *          0 < yMin < yMax
 *          0 < xMax < xTotal
 *
 * ----------------------------------------------------------------------------
 */

contract ConstantProductBondingCurve is ICurve {
	uint256 internal constant Q_DENOM = 10_000;

	/**
	 * @notice  Validate whether given parameters are compatible with this math implementation
	 *
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  True if compatible, false if not
	 */
	function checkCompatability(
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) public pure returns (bool) {
		return yMax >= yMin && yMin > 0 && xMax > 0 && xTotal > xMax;
	}

	/**
	 * @notice  Get the price of the `x`th unit of token
	 *
	 * @param   x       Wei of tokens
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  Price of the `x`th token, wei ETH per 1e18 wei tokens
	 */
	function fPrimeX(
		uint256 x,
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) public pure returns (uint256) {
		if (!checkCompatability(yMin, yMax, xMax, xTotal))
			revert ICurve__InvalidInput();
		uint256 k = getK(xTotal, xMax, yMax);
		uint256 q = getQ(yMin, yMax);
		return
			Math.mulDiv(
				k,
				1e18,
				(((q * xTotal) / Q_DENOM - x) ** 2),
				Math.Rounding.Floor
			);
	}

	/**
	 * @notice  Get the ETH value of `x` amount of tokens
	 *
	 * @param   x       Wei of tokens
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  Total value, wei of ETH
	 */
	function fX(
		uint256 x,
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) public pure returns (uint256) {
		if (!checkCompatability(yMin, yMax, xMax, xTotal))
			revert ICurve__InvalidInput();
		uint256 k = getK(xTotal, xMax, yMax);
		uint256 q = getQ(yMin, yMax);
		return k / ((q * xTotal) / Q_DENOM - x) - k / ((q * xTotal) / Q_DENOM);
	}

	/**
	 * @notice  Get the token value of `y` amount of ETH
	 *
	 * @param   y       Wei of ETH
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  Total value, wei of token
	 */
	function fY(
		uint256 y,
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) public pure returns (uint256) {
		if (!checkCompatability(yMin, yMax, xMax, xTotal))
			revert ICurve__InvalidInput();
		if (y == 0) return 0;
		uint256 k = getK(xTotal, xMax, yMax);
		uint256 q = getQ(yMin, yMax);
		return
			Math.mulDiv(
				((q * xTotal) / Q_DENOM) ** 2,
				y,
				(q * xTotal * y) / Q_DENOM + k
			);
	}

	/**
	 * @notice  Get the ETH value between `x1` and `x2` amounts of token
	 *
	 * @param   x1      Wei of token, starting
	 * @param   x1      Wei of token, ending
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  Total value, wei of ETH
	 */
	function evaluateDx(
		uint256 x1,
		uint256 x2,
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) external pure returns (uint256) {
		if (x1 > x2) revert ICurve__InvalidInput();
		return
			fX(x2, yMin, yMax, xMax, xTotal) - fX(x1, yMin, yMax, xMax, xTotal);
	}

	/**
	 * @notice  Get the token value between `y1` and `y2` amounts of ETH
	 *
	 * @param   y1      Wei of ETH, starting
	 * @param   y1      Wei of ETH, ending
	 * @param   yMin    Minimum price parameter, wei ETH per 1e18 wei tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 *
	 * @return  Total value, wei of token
	 */
	function evaluateDy(
		uint256 y1,
		uint256 y2,
		uint256 yMin,
		uint256 yMax,
		uint256 xMax,
		uint256 xTotal
	) external pure returns (uint256) {
		if (y1 > y2) revert ICurve__InvalidInput();
		return
			fY(y2, yMin, yMax, xMax, xTotal) - fY(y1, yMin, yMax, xMax, xTotal);
	}

	/**
	 * @notice  Calculate the liquidity constant k for the curve
	 *
	 * @param   xTotal  Total supply of tokens, wei of tokens
	 * @param   xMax    Maximum amount of tokens in the bonding curve, wei of tokens
	 * @param   yMax    Maximum price parameter, wei ETH per 1e18 wei tokens
	 *
	 * @return  k, wei of ETH * wei of token
	 */
	function getK(
		uint256 xTotal,
		uint256 xMax,
		uint256 yMax
	) public pure returns (uint256) {
		uint256 k = Math.mulDiv((xTotal - xMax) ** 2, yMax, 1e18);
		console.log("k", k);
		return k;
	}

	/**
	 * @notice  Calculate the tuning factor for the curve
	 */
	function getQ(uint256 yMin, uint256 yMax) public pure returns (uint256) {
		uint256 q = (yMax * Q_DENOM) / yMin;
		console.log("q", q);
		return q;
	}
}
