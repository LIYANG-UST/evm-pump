// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { IWETH } from "../interfaces/IWETH.sol";

import { LaunchpadToken } from "./LaunchpadToken.sol";
import { ICurve } from "../interfaces/ICurve.sol";
import "hardhat/console.sol";

/**
 * @title Gauge
 *
 * @notice Trades a token along a bonding curve, with the ability to launch a Uniswap V3 pool
 */
contract Gauge is Initializable {
    ////////////////////////////////////////////////////////////////////////////////
    // CONSTANTS AND IMMUTABLES
    ////////////////////////////////////////////////////////////////////////////////

    /// @dev Minimum token purchase amount
    uint256 public constant MIN_BUY = 10e18; // 1 token

    /// @dev Fraction denominator
    uint256 public constant FRACTION_DENOMINATOR = 1e18;

    /// @dev Maximum buy fee (1e18 = 100%)
    uint256 public constant MAX_BUY_FEE = 0.05e18; // 5%
    /// @dev Maximum sell fee (1e18 = 100%)
    uint256 public constant MAX_SELL_FEE = 0.05e18; // 5%

    INonfungiblePositionManager public immutable UNISWAP_V3_NFT_MANAGER;
    IWETH public immutable weth;
    address public immutable feeReceiver;

    ////////////////////////////////////////////////////////////////////////////////
    // STATE
    ////////////////////////////////////////////////////////////////////////////////

    LaunchpadToken public token;
    ICurve public curve;
    address public lpReceiver;
    address public pool;

    struct CurveParameters {
        uint128 yMin;
        uint128 yMax;
    }
    CurveParameters public curveParameters;

    struct FeeParameters {
        uint128 buyFee;
        uint128 sellFee;
    }
    FeeParameters public feeParameters;

    /// @notice Amount of token purchased
    uint256 public tokenPurchased;
    /// @notice Total ETH paid into the curve
    uint256 public ethPaid;
    /// @notice Target amount of tokens to purchase during the curve
    uint256 public tokenTarget;
    /// @notice Total supply of the token
    uint256 public totalSupply;

    ////////////////////////////////////////////////////////////////////////////////
    // CONSTRUCTION AND INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    constructor(INonfungiblePositionManager _nftManager, IWETH _weth, address _feeReceiver) {
        if (address(_nftManager) == address(0) || address(_weth) == address(0) || _feeReceiver == address(0))
            revert Gauge__ZeroAddress();

        UNISWAP_V3_NFT_MANAGER = _nftManager;
        weth = _weth;
        feeReceiver = _feeReceiver;
        _disableInitializers();
    }

    modifier isActive() {
        if (!gaugeActive()) revert Gauge__GaugeClosed();
        _;
    }

    function initialize(
        LaunchpadToken _token,
        ICurve _curve,
        address _lpReceiver,
        uint256 _amount,
        uint256 _tokenTarget,
        CurveParameters memory _curveParameters,
        FeeParameters memory _feeParameters
    ) public initializer {
        if (address(_token) == address(0) || address(_curve) == address(0) || _lpReceiver == address(0)) {
            revert Gauge__ZeroAddress();
        }
        if (_amount == 0 || _amount < _tokenTarget) revert Gauge__InvalidAmount();
        if (_tokenTarget == 0) revert Gauge__InvalidTokenTarget();

        uint256 cachedTotalSupply = _token.totalSupply();
        if (!_curve.checkCompatability(_curveParameters.yMin, _curveParameters.yMax, _tokenTarget, cachedTotalSupply)) {
            revert Gauge__InvalidCurveParameters();
        }
        if (_feeParameters.buyFee > MAX_BUY_FEE || _feeParameters.sellFee > MAX_SELL_FEE) revert Gauge__ExcessiveFee();

        token = _token;
        curve = _curve;
        lpReceiver = _lpReceiver;
        tokenTarget = _tokenTarget;
        curveParameters = _curveParameters;
        feeParameters = _feeParameters;
        totalSupply = cachedTotalSupply;

        token.transferFrom(msg.sender, address(this), _amount);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // TRADING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Buy exactly `_amount` of tokens, paying whatever cost is necessary
     * @dev     If less than `_amount` of tokens remain in the curve, the user will receive the remaining tokens
     * @dev     Any msg.value in excess of the actual cost will be forwarded to `_recipient`
     * @dev     Maximum input amount is defined by msg.value
     * @param   _recipient  Address to receive the tokens
     * @param   _amount     Amount of tokens to buy
     */
    function buyExactTokens(address _recipient, uint256 _amount) public payable isActive {
        uint256 amountToPurchase = _amount > tokenTarget - tokenPurchased ? tokenTarget - tokenPurchased : _amount;
        if (amountToPurchase < MIN_BUY) revert Gauge__MinBuy();

        (uint256 cost, uint256 fee) = quoteBuyExactTokens(amountToPurchase);
        if (msg.value < cost) revert Gauge__InsufficientPayment();

        uint256 startingPrice = getCurrentPrice();
        tokenPurchased += amountToPurchase;
        ethPaid += cost - fee;
        token.transfer(_recipient, amountToPurchase);

        if (fee > 0) {
            (bool success, ) = payable(feeReceiver).call{ value: fee }("");
            if (!success) revert Gauge__TransferFailure();
        }
        if (msg.value > cost) payable(_recipient).transfer(msg.value - cost);

        emit Buy(_recipient, amountToPurchase, cost, startingPrice);
    }

    /**
     * @notice  Sell exactly `_amountIn` of tokens to ETH
     * @param   _recipient      Address to receive the proceeds
     * @param   _amountIn       Amount of tokens to sell
     * @param   _minAmountOut   Minimum amount of ETH to receive
     */
    function sellExactTokens(address _recipient, uint256 _amountIn, uint256 _minAmountOut) public isActive {
        if (_amountIn == 0 || _amountIn > tokenPurchased) revert Gauge__InvalidAmount();
        (uint256 proceeds, uint256 fee) = quoteSellExactTokens(_amountIn);

        if (proceeds < _minAmountOut) revert Gauge__InsufficientOutput();

        uint256 startingPrice = getCurrentPrice();
        tokenPurchased -= _amountIn;
        ethPaid -= proceeds + fee;
        token.transferFrom(msg.sender, address(this), _amountIn);

        if (fee > 0) {
            (bool success, ) = payable(feeReceiver).call{ value: fee }("");
            if (!success) revert Gauge__TransferFailure();
        }
        payable(_recipient).transfer(proceeds);

        emit Sell(_recipient, _amountIn, proceeds, startingPrice);
    }

    /**
     * @notice  Buy tokens with an exact amount of ETH, receiving as many tokens as possible
     * @dev     If less than `_minAmount` of tokens remain in the curve, the user will receive the remaining tokens
     * @param   _recipient      Address to receive the tokens
     * @param   _minAmountOut   Minimum amount of tokens to receive
     */
    function buyExactEth(address _recipient, uint256 _minAmountOut) public payable isActive {
        uint256 cost = msg.value;

        (uint256 tokensOut, uint256 fee) = quoteBuyExactEth(cost);
        if (tokensOut < _minAmountOut) revert Gauge__InsufficientOutput();

		console.log("tokens out", tokensOut);

        // Handle case where less than max is available
        if (tokensOut > tokenTarget - tokenPurchased) {
            tokensOut = tokenTarget - tokenPurchased;
            (cost, fee) = quoteBuyExactTokens(tokensOut);
            if (msg.value < cost) revert Gauge__InsufficientPayment();
        }

        if (tokensOut < MIN_BUY) revert Gauge__MinBuy();

        uint256 startingPrice = getCurrentPrice();
        tokenPurchased += tokensOut;
        ethPaid += cost - fee;
        token.transfer(_recipient, tokensOut);

        if (fee > 0) {
            (bool success, ) = payable(feeReceiver).call{ value: fee }("");
            if (!success) revert Gauge__TransferFailure();
        }
        if (msg.value > cost) payable(_recipient).transfer(msg.value - cost);

        emit Buy(_recipient, tokensOut, cost, startingPrice);
    }

    /**
     * @notice  Sell tokens for an exact amount of ETH, selling as few tokens as possible
     * @param   _recipient      Address to receive the proceeds
     * @param   _amountOut      Amount of ETH to receive
     * @param   _maxInput       Maximum amount of tokens to sell
     */
    function sellExactEth(address _recipient, uint256 _amountOut, uint256 _maxInput) public isActive {
        if (_amountOut == 0) revert Gauge__InvalidAmount();
        (uint256 tokensIn, uint256 fee) = quoteSellExactEth(_amountOut);
        if (tokensIn > _maxInput) revert Gauge__MaxInputExceeded();

        uint256 startingPrice = getCurrentPrice();
        tokenPurchased -= tokensIn;
        ethPaid -= _amountOut + fee;
        token.transferFrom(msg.sender, address(this), tokensIn);

        if (fee > 0) {
            (bool success, ) = payable(feeReceiver).call{ value: fee }("");
            if (!success) revert Gauge__TransferFailure();
        }
        payable(_recipient).transfer(_amountOut);

        emit Sell(_recipient, tokensIn, _amountOut, startingPrice);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // BONDING CURVE COMPLETION
    ////////////////////////////////////////////////////////////////////////////////

    function launchPool() external isActive returns (address, uint256) {
        if (!gaugeClosable()) revert Gauge__BondingCurveNotMature();

        // Close the gauge
        tokenPurchased = 0;
        tokenTarget = 0;
        ethPaid = 0;

        // Convert native token to WETH
        weth.deposit{ value: address(this).balance }();

        // Make approvals
        token.approve(address(UNISWAP_V3_NFT_MANAGER), type(uint256).max);
        weth.approve(address(UNISWAP_V3_NFT_MANAGER), type(uint256).max);

        // Sort tokens
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
            amount0 = token.balanceOf(address(this));
            amount1 = weth.balanceOf(address(this));
        } else {
            token0 = address(weth);
            token1 = address(token);
            amount0 = weth.balanceOf(address(this));
            amount1 = token.balanceOf(address(this));
        }

        // Calculate sqrtprice, accounting for rounding in cases where amount1 < amount0
        uint256 sqrtPriceX96 = (Math.sqrt((amount1 * 1e18) / amount0) * 2 ** 96) / 1e9;

        // Create and initialize a pool on Uniswap V3
        address _pool = UNISWAP_V3_NFT_MANAGER.createAndInitializePoolIfNecessary(
            token0,
            token1,
            10_000,
            uint160(sqrtPriceX96)
        );
        pool = _pool;

        // Create the LP
        (uint256 tokenId, , , ) = UNISWAP_V3_NFT_MANAGER.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: 10_000,
                tickLower: -887_200,
                tickUpper: 887_200,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 1,
                amount1Min: 1,
                recipient: lpReceiver,
                deadline: block.timestamp
            })
        );

        // Sweep any dust to the LP receiver
        if (weth.balanceOf(address(this)) > 0) weth.transfer(lpReceiver, weth.balanceOf(address(this)));
        if (token.balanceOf(address(this)) > 0) token.transfer(lpReceiver, token.balanceOf(address(this)));

        emit PoolLaunched(address(token), _pool, tokenId);

        return (_pool, tokenId);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // VIEW
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice True if gauge is active
    function gaugeActive() public view returns (bool) {
        return tokenTarget != 0;
    }

    function gaugeClosable() public view returns (bool) {
        return (tokenTarget - tokenPurchased) < MIN_BUY;
    }

    /**
     * @notice  Get the current price of the token
     * @return  Current price of the token, in wei of ETH per 1e18 wei of token
     */
    function getCurrentPrice() public view returns (uint256) {
        if (!gaugeActive()) {
            return 0;
        } else {
            return curve.fPrimeX(tokenPurchased, curveParameters.yMin, curveParameters.yMax, tokenTarget, totalSupply);
        }
    }

    /**
     * @notice  Get the current statistics of the gauge
	 *
     * @return  active          True if the gauge is active
     * @return  closable        True if the gauge is closable
     * @return  tokens          Amount of tokens purchased
     * @return  target          Target amount of tokens to purchase
     * @return  supply          Total supply of the token
     * @return  eth             Total ETH paid into the curve
     * @return  currentPrice    Current price of the token, in wei of ETH per 1e18 wei of token
     */
    function getGaugeStatistics()
        external
        view
        returns (
            bool active,
            bool closable,
            uint256 tokens,
            uint256 target,
            uint256 supply,
            uint256 eth,
            uint256 currentPrice
        )
    {
        active = gaugeActive();
        closable = gaugeClosable();
        tokens = tokenPurchased;
        target = tokenTarget;
        supply = totalSupply;
        eth = ethPaid;
        currentPrice = getCurrentPrice();
    }

    /**
     * @notice  Get the ETH cost of buying `_amount` of tokens, inclusive of any fees
     * @param   _amount Amount of tokens to buy
     * @return  total cost: Amount the user pays, in wei of ETH
     * @return  fee:        Fee that was added to the raw cost, in wei of ETH
     */
    function quoteBuyExactTokens(uint256 _amount) public view returns (uint256, uint256) {
        uint256 rawCost = curve.evaluateDx(
            tokenPurchased,
            tokenPurchased + _amount,
            curveParameters.yMin,
            curveParameters.yMax,
            tokenTarget,
            totalSupply
        );

        uint256 fee = (rawCost * feeParameters.buyFee) / FRACTION_DENOMINATOR;

        return (rawCost + fee, fee);
    }

    /**
     * @notice  Get the ETH proceeds of selling `_amount` of tokens, inclusive of any fees
     * @param   _amount Amount of tokens to sell
     * @return  total proceeds: Amount the user receives, in wei of ETH
     * @return  fee:            Fee that was subtracted from the raw proceeds, in wei of ETH
     */
    function quoteSellExactTokens(uint256 _amount) public view returns (uint256, uint256) {
        if (_amount > tokenPurchased) revert Gauge__DesiredExceedsAvailable();
        uint256 rawProceeds = curve.evaluateDx(
            tokenPurchased - _amount,
            tokenPurchased,
            curveParameters.yMin,
            curveParameters.yMax,
            tokenTarget,
            totalSupply
        );

        uint256 fee = (rawProceeds * feeParameters.sellFee) / FRACTION_DENOMINATOR;

        return (rawProceeds - fee, fee);
    }

    /**
     * @notice  Get the number of tokens which will cost `_amount` of ETH, inclusive of any fees
     * @param   _amount Amount of ETH to spend
     * @return  tokensOut:  Amount of tokens the user will receive
     * @return  fee:        Fee that was subtracted from the user's purchasing power, in wei of ETH
     */
    function quoteBuyExactEth(uint256 _amount) public view returns (uint256, uint256) {
        uint256 fee = (_amount * feeParameters.buyFee) / FRACTION_DENOMINATOR;

        uint256 tokensOut = curve.evaluateDy(
            ethPaid,
            (ethPaid + _amount - fee),
            curveParameters.yMin,
            curveParameters.yMax,
            tokenTarget,
            totalSupply
        );

        return (tokensOut, fee);
    }

    /**
     * @notice  Get the number of tokens which must be sold to receive `_amount` of ETH, inclusive of any fees
     * @param   _amount Amount of ETH to receive
     * @return  tokensIn:   Amount of tokens the user will pay
     * @return  fee:        Fee that was added to the raw desired amount, in wei of ETH
     */
    function quoteSellExactEth(uint256 _amount) public view returns (uint256, uint256) {
        uint256 fee = (_amount * feeParameters.sellFee) / FRACTION_DENOMINATOR;
        if (_amount + fee > ethPaid) revert Gauge__DesiredExceedsAvailable();

        uint256 tokensIn = curve.evaluateDy(
            (ethPaid - _amount - fee),
            ethPaid,
            curveParameters.yMin,
            curveParameters.yMax,
            tokenTarget,
            totalSupply
        );

        return (tokensIn, fee);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////////

    error Gauge__ZeroAddress();
    error Gauge__InvalidAmount();
    error Gauge__InvalidTokenTarget();
    error Gauge__InvalidCurveParameters();
    error Gauge__InsufficientPayment();
    error Gauge__MinBuy();
    error Gauge__BondingCurveNotMature();
    error Gauge__GaugeClosed();
    error Gauge__ExcessiveFee();
    error Gauge__InsufficientOutput();
    error Gauge__MaxInputExceeded();
    error Gauge__DesiredExceedsAvailable();
    error Gauge__TransferFailure();

    ////////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////////

    event Buy(address indexed recipient, uint256 amount, uint256 cost, uint256 startingPrice);
    event Sell(address indexed recipient, uint256 amount, uint256 proceeds, uint256 startingPrice);
    event PoolLaunched(address indexed token, address indexed pool, uint256 tokenId);
}
