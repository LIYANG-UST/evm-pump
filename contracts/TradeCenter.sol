// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.20;

// contract TradeCenter {
//     /**
//      * @notice  Buy an exact amount of tokens
//      * @dev     Allowable slippage is defined by msg.value
//      * @param   token       Token address
//      * @param   amountOut   Amount of tokens to buy
//      */
//     function buyExactTokens(address token, uint256 amountOut) external payable {
//         Gauge gauge = Gauge(tokenToGauge[token]);
//         if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

//         gauge.buyExactTokens{ value: msg.value }(msg.sender, amountOut);
//     }

//     /**
//      * @notice  Sell an exact amount of tokens
//      * @param   token           Token address
//      * @param   amountIn        Amount of tokens to sell
//      * @param   minAmountOut    Minimum amount of ETH to receive
//      */
//     function sellExactTokens(address token, uint256 amountIn, uint256 minAmountOut) external {
//         Gauge gauge = Gauge(tokenToGauge[token]);
//         if (address(gauge) == address(0)) revert Launchpad__InvalidToken();
//         LaunchpadToken(token).transferFrom(msg.sender, address(this), amountIn);
//         gauge.sellExactTokens(msg.sender, amountIn, minAmountOut);
//     }

//     /**
//      * @notice  Buy the maximum amount of tokens for an exact ETH input
//      * @param   token           Token address
//      * @param   minAmountOut    Minimum amount of tokens to receive
//      */
//     function buyExactEth(address token, uint256 minAmountOut) external payable {
//         Gauge gauge = Gauge(tokenToGauge[token]);
//         if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

//         gauge.buyExactEth{ value: msg.value }(msg.sender, minAmountOut);
//     }

//     /**
//      * @notice  Sell the minimum amount of tokens for an exact ETH output
//      * @param   token       Token address
//      * @param   amountOut   Amount of ETH to receive
//      * @param   maxInput    Maximum amount of tokens to sell
//      */
//     function sellExactEth(address token, uint256 amountOut, uint256 maxInput) external {
//         Gauge gauge = Gauge(tokenToGauge[token]);
//         if (address(gauge) == address(0)) revert Launchpad__InvalidToken();
//         (uint256 amountIn, ) = gauge.quoteSellExactEth(amountOut);
//         LaunchpadToken(token).transferFrom(msg.sender, address(this), amountIn);
//         gauge.sellExactEth(msg.sender, amountOut, maxInput);
//     }
// }
