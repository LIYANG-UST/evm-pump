// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Gauge } from "./tokens/Gauge.sol";
import { LaunchpadToken } from "./tokens/LaunchpadToken.sol";
import { ICurve } from "./interfaces/ICurve.sol";
import { ITreasury } from "./interfaces/ITreasury.sol";

import "hardhat/console.sol";

/**
 * --------------------------------------------------------------------------------
 *
 * @title   Launchpad
 * @notice  Platform entry point for creating and trading tokens
 * @author  BowTiedPickle
 *
 * --------------------------------------------------------------------------------
 */
contract Launchpad is Ownable {
    // ---------------------------------------------------------------------------------------- //
    // ************************************** Libraries *************************************** //
    // ---------------------------------------------------------------------------------------- //

    using EnumerableSet for EnumerableSet.AddressSet;

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Constants *************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Maximum fraction of supply of a new token which can be reserved for booster program (1e18 = 100%)
    uint256 public constant MAX_BOOSTER_FRACTION = 0.2e18; // 2%

    // Maximum fraction of supply of a new token which can be used in the bonding curve (1e18 = 100%)
    uint256 public constant MAX_BONDING_FRACTION = 0.98e18; // 98%

    // Fraction demoninator
    uint256 public constant FRACTION_DENOMINATOR = 1e18;

    // Maximum creation cost which can be charged (wei of ETH)
    uint256 public constant MAX_CREATION_COST = 1 ether;

    // Maximum buy/sell fee which is allowed in a gauge
    uint256 public constant MAX_GAUGE_FEE = 2.5e16; // 2.5%

    // Minimum initial supply allowed for a token
    uint256 public constant MIN_INITIAL_SUPPLY = 100 ether;

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Variables *************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Address of the token implementation
    // Clones of this contract code will be used to create new tokens
    // Can be updated to new versions (will not change the behavior of existing tokens)
    address public tokenImplementation;

    // Address of the gauge implementation
    address public gaugeImplementation;

    /// @notice Address of the bonding curve math implementation
    address public bondingcurve;

    // Cost to create a new token (in ETH)
    uint256 public creationCost;

    // Booster treasury address
    address public treasury;

    // Address which will receive LP tokens when pools are created from a gauge
    address public lpReceiver;

    // Fee parameters applied to new gauges
    Gauge.FeeParameters public gaugeFees;

    // All created tokens
    EnumerableSet.AddressSet internal tokens;

    mapping(address token => address gauge) public tokenToGauge;
    mapping(address token => address creator) public tokenToCreator;

    mapping(address creator => EnumerableSet.AddressSet tokens) internal creatorToTokens;

    mapping(string tokenName => address token) public tokenNameToAddress;

    struct AutoSnipeConfig {
        uint256 minAmountOut;
    }

    // Total = booster + bonding curve + remaining
    // e.g. 20% to airdrop, 60% sold by bonding curve, 20% for later DEX liquidity
    struct FractionConfig {
        uint256 boosterFraction;
        uint256 bondingCurveFraction;
    }

    // ---------------------------------------------------------------------------------------- //
    // **************************************** Events **************************************** //
    // ---------------------------------------------------------------------------------------- //

    event NewToken(address indexed creator, address indexed token, address indexed gauge, address curve);

    event TokenImplementationSet(address indexed newImpl, address indexed oldImpl);
    event GaugeImplementationSet(address indexed newImpl, address indexed oldImpl);
    event CurveSet(address indexed newCurve, address indexed oldCurve);
    event TreasurySet(address indexed newTreasury, address indexed oldTreasury);
    event LpReceiverSet(address indexed newReceiver, address indexed oldReceiver);
    event CreationCostSet(uint256 newAmount, uint256 oldAmount);
    event GaugeFeesSet(uint256 newBuyFee, uint256 oldBuyFee, uint256 newSellFee, uint256 oldSellFee);

    // ---------------------------------------------------------------------------------------- //
    // **************************************** Errors **************************************** //
    // ---------------------------------------------------------------------------------------- //

    error Launchpad__ZeroAddress();
    error Launchpad__InvalidTotalSupply();
    error Launchpad__InsufficientValue();
    error Launchpad__InvalidToken();
    error Launchpad__ExcessiveCreationCost();
    error Launchpad__ExcessiveFraction();
    error Launchpad__ExcessiveGaugeFee();
    error Launchpad__ExcessiveBondingFraction();
    error Launchpad__InvalidIndex();
    error Launchpad__TransferFailure();
    error Launchpad__DuplicateTokenName();

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Constructor *************************************** //
    // ---------------------------------------------------------------------------------------- //

    constructor(
        address _tokenImplementation,
        address _gaugeImplementation,
        address _bondingcurve,
        address _treasury,
        address _lpReceiver,
        uint256 _creationCost
    ) Ownable(msg.sender) {
        if (
            _tokenImplementation == address(0) ||
            _gaugeImplementation == address(0) ||
            _bondingcurve == address(0) ||
            _treasury == address(0) ||
            _lpReceiver == address(0)
        ) revert Launchpad__ZeroAddress();
        if (_creationCost > MAX_CREATION_COST) revert Launchpad__ExcessiveCreationCost();

        tokenImplementation = _tokenImplementation;
        gaugeImplementation = _gaugeImplementation;
        bondingcurve = _bondingcurve;
        treasury = _treasury;
        lpReceiver = _lpReceiver;
        creationCost = _creationCost;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Create a new token and its gauge
     *         Send more ETH than the creation cost to trigger an autosnipe with the excess
     *
     * @param tokenConfig     Token configuration
     * @param metadataConfig  Token metadata configuration
     * @param snipeConfig     Autosnipe configuration
     * @param curveParameters Bonding curve price parameters
     *
     * @return token Token address
     * @return gauge Gauge address
     */
    function createLaunchpadToken(
        LaunchpadToken.TokenConfig memory tokenConfig,
        LaunchpadToken.TokenMetadataConfig memory metadataConfig,
        AutoSnipeConfig memory snipeConfig,
        Gauge.CurveParameters memory curveParameters,
        FractionConfig memory fractionConfig
    ) external payable returns (LaunchpadToken, Gauge) {
        if (msg.value < creationCost) revert Launchpad__InsufficientValue();
        if (fractionConfig.bondingCurveFraction + fractionConfig.boosterFraction >= FRACTION_DENOMINATOR)
            revert Launchpad__ExcessiveFraction();

        uint256 totalSupply = tokenConfig.initialSupply;
		console.log("totalSupply", totalSupply / 1e18);

        // Create token and gauge
        (LaunchpadToken token, Gauge gauge) = _createTokenAndGauge(
            tokenConfig,
            metadataConfig,
            fractionConfig.boosterFraction
        );

        // Initialize the gauge
        gauge.initialize(
            token,
            ICurve(bondingcurve),
            lpReceiver,
            // Total amount - booster amount
            totalSupply - (totalSupply * fractionConfig.boosterFraction) / FRACTION_DENOMINATOR,
            // Target amount for the bonding curve (deploy on DEX after reaching this target)
            (totalSupply * fractionConfig.bondingCurveFraction) / FRACTION_DENOMINATOR,
            curveParameters,
            gaugeFees
        );

        // Take creation cost - call used due to multisig recipient
        (bool success, ) = payable(treasury).call{ value: creationCost }("");
        if (!success) revert Launchpad__TransferFailure();

        // Autosnipe
        if (msg.value > creationCost) {
            gauge.buyExactEth{ value: msg.value - creationCost }(msg.sender, snipeConfig.minAmountOut);
        }

        emit NewToken(msg.sender, address(token), address(gauge), bondingcurve);

        return (token, gauge);
    }

    /**
     * @notice Deploy a new token and its gauge, and initialize the token
     */
    function _createTokenAndGauge(
        LaunchpadToken.TokenConfig memory tokenConfig,
        LaunchpadToken.TokenMetadataConfig memory metadataConfig,
        uint256 _boosterFraction
    ) internal returns (LaunchpadToken, Gauge) {
        if (tokenConfig.initialSupply < MIN_INITIAL_SUPPLY) revert Launchpad__InvalidTotalSupply();

        if (tokenNameToAddress[tokenConfig.name] != address(0)) revert Launchpad__DuplicateTokenName();

        LaunchpadToken token = LaunchpadToken(Clones.clone(tokenImplementation));
        Gauge gauge = Gauge(Clones.clone(gaugeImplementation));

        tokenToGauge[address(token)] = address(gauge);
        tokens.add(address(token));
        creatorToTokens[msg.sender].add(address(token));
        tokenToCreator[address(token)] = msg.sender;

        // Token name to address mapping (name must be unique)
        tokenNameToAddress[tokenConfig.name] = address(token);

        token.initialize(tokenConfig, metadataConfig, address(gauge));

        uint256 boosterFractionAmount = (tokenConfig.initialSupply * _boosterFraction) / FRACTION_DENOMINATOR;
        token.transfer(treasury, boosterFractionAmount);
		ITreasury(treasury).receiveAirdrop(address(token), boosterFractionAmount);

        // Max approval to enable router functions later
        token.approve(address(gauge), type(uint256).max);

        return (token, gauge);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // TRADE TOKENS
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Buy an exact amount of tokens
     * @dev     Allowable slippage is defined by msg.value
     * @param   token       Token address
     * @param   amountOut   Amount of tokens to buy
     */
    function buyExactTokens(address token, uint256 amountOut) external payable {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        gauge.buyExactTokens{ value: msg.value }(msg.sender, amountOut);
    }

    /**
     * @notice  Sell an exact amount of tokens
     * @param   token           Token address
     * @param   amountIn        Amount of tokens to sell
     * @param   minAmountOut    Minimum amount of ETH to receive
     */
    function sellExactTokens(address token, uint256 amountIn, uint256 minAmountOut) external {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();
        LaunchpadToken(token).transferFrom(msg.sender, address(this), amountIn);
        gauge.sellExactTokens(msg.sender, amountIn, minAmountOut);
    }

    /**
     * @notice  Buy the maximum amount of tokens for an exact ETH input
     * @param   token           Token address
     * @param   minAmountOut    Minimum amount of tokens to receive
     */
    function buyExactEth(address token, uint256 minAmountOut) external payable {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        gauge.buyExactEth{ value: msg.value }(msg.sender, minAmountOut);
    }

    /**
     * @notice  Sell the minimum amount of tokens for an exact ETH output
     * @param   token       Token address
     * @param   amountOut   Amount of ETH to receive
     * @param   maxInput    Maximum amount of tokens to sell
     */
    function sellExactEth(address token, uint256 amountOut, uint256 maxInput) external {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();
        (uint256 amountIn, ) = gauge.quoteSellExactEth(amountOut);
        LaunchpadToken(token).transferFrom(msg.sender, address(this), amountIn);
        gauge.sellExactEth(msg.sender, amountOut, maxInput);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // VIEWS
    ////////////////////////////////////////////////////////////////////////////////

    // ---------- Quotes ----------

    enum QuoteType {
        BUY_EXACT_TOKENS,
        SELL_EXACT_TOKENS,
        BUY_EXACT_ETH,
        SELL_EXACT_ETH
    }

    struct Quote {
        // Wei of ETH the user will pay for the action
        uint256 amountInEth;
        // Wei of tokens the user will pay for the action
        uint256 amountInToken;
        // Wei of ETH the user will receive
        uint256 amountOutEth;
        // Wei of tokens the user will receive
        uint256 amountOutToken;
    }

    /**
     * @notice  Get a quote for a trade at the prevailing conditions
     *          The price may change from this value, set slippage accordingly
     *
     * @param   token       Token address
     * @param   amount      Amount of tokens to buy/sell
     * @param   quoteType   Type of trade to quote
     *
     * @return  quote       Quote struct
     */
    function quote(address token, uint256 amount, QuoteType quoteType) external view returns (Quote memory) {
        Quote memory result = Quote(0, 0, 0, 0);
        uint256 value;
        if (quoteType == QuoteType.BUY_EXACT_TOKENS) {
            (amount, value) = quoteBuyExactTokens(token, amount);
            result.amountInEth = value;
            result.amountOutToken = amount;
        } else if (quoteType == QuoteType.SELL_EXACT_TOKENS) {
            (amount, value) = quoteSellExactTokens(token, amount);
            result.amountInToken = amount;
            result.amountOutEth = value;
        } else if (quoteType == QuoteType.BUY_EXACT_ETH) {
            (amount, value) = quoteBuyExactEth(token, amount);
            result.amountInEth = amount;
            result.amountOutToken = value;
        } else if (quoteType == QuoteType.SELL_EXACT_ETH) {
            (amount, value) = quoteSellExactEth(token, amount);
            result.amountInToken = value;
            result.amountOutEth = amount;
        }
        return result;
    }

    /**
     * @notice  Get the ETH cost of buying `amount` of tokens, inclusive of any fees
     * @dev     If `amount` exceeds the amount available to purchase, it will be clamped to the available amount
     * @param   token   Token address
     * @param   amount  Amount of tokens to buy
     * @return  amount:     Amount of tokens being purchased
     * @return  total cost: Amount the user pays, in wei of ETH
     */
    function quoteBuyExactTokens(address token, uint256 amount) public view returns (uint256, uint256) {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        uint256 remaining = gauge.tokenTarget() - gauge.tokenPurchased();
        amount = amount > remaining ? remaining : amount;
        (uint256 result, ) = gauge.quoteBuyExactTokens(amount);

        return (amount, result);
    }

    /**
     * @notice  Get the ETH proceeds of selling `amount` of tokens, inclusive of any fees
     * @dev     If `amount` exceeds the amount of tokens purchased, it will be clamped to the available amount
     * @param   token   Token address
     * @param   amount  Amount of tokens to sell
     * @return  total proceeds: Amount the user receives, in wei of ETH
     */
    function quoteSellExactTokens(address token, uint256 amount) public view returns (uint256, uint256) {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        uint256 available = gauge.tokenPurchased();
        amount = amount > available ? available : amount;
        (uint256 result, ) = gauge.quoteSellExactTokens(amount);
        return (amount, result);
    }

    /**
     * @notice  Get the number of tokens which will cost `amount` of ETH, inclusive of any fees
     * @param   token   Token address
     * @param   amount  Amount of ETH to spend
     * @return  tokensOut:  Amount of tokens the user will receive
     */
    function quoteBuyExactEth(address token, uint256 amount) public view returns (uint256, uint256) {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        // returns (tokensOut, fee in eth)
        (uint256 result, ) = gauge.quoteBuyExactEth(amount);

        // Remaining tokens to be bought
        uint256 remaining = gauge.tokenTarget() - gauge.tokenPurchased();
        
        // If the amount of tokens to be bought exceeds the remaining amount
        // Get how 
        if (result > remaining) {
            result = remaining;

            // returns (total cost in eth, fee in eth)
            (amount, ) = gauge.quoteBuyExactTokens(remaining);
        }

        // The first return value is 
        return (amount, result);
    }

    /**
     * @notice  Get the number of tokens which must be sold to receive `amount` of ETH, inclusive of any fees
     * @param   token   Token address
     * @param   amount  Amount of ETH to receive
     * @return  tokensIn:   Amount of tokens the user will pay
     */
    function quoteSellExactEth(address token, uint256 amount) public view returns (uint256, uint256) {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();

        (, uint256 sellFee) = gauge.feeParameters();
        uint256 available = (gauge.ethPaid() * (FRACTION_DENOMINATOR - sellFee)) / FRACTION_DENOMINATOR;
        amount = amount > available ? available : amount;
        (uint256 result, ) = gauge.quoteSellExactEth(amount);

        return (amount, result);
    }

    // ---------- Tokens and Token Info ----------

    struct TokenInfo {
        // Token address
        address token;
        // Gauge address
        address gauge;
        // Token name
        string name;
        // Token symbol
        string symbol;
        // True if gauge is active
        bool gaugeActive;
        // True if gauge is closable
        bool gaugeClosable;
        // Number of tokens purchased in the gauge
        uint256 tokenPurchased;
        // Target number of tokens in the gauge
        uint256 tokenTarget;
        // Total supply of the token
        uint256 totalSupply;
        // Current price in wei of ETH per 1e18 wei of token
        uint256 currentPrice;
        // ETH paid into the gauge
        uint256 ethPaid;
        // Fractional fee charged on buy (1e18 = 100%)
        uint128 buyFee;
        // Fractional fee charged on sell (1e18 = 100%)
        uint128 sellFee;
        // Metadata
        LaunchpadToken.TokenMetadataConfig metadata;
        // Token creator address
        address creator;
        // Pool address
        address pool;
    }

    /**
     * @notice  Get the current information of a given token and its gauge
     * @param   token       Token address
     * @return  tokenInfo   TokenInfo struct
     */
    function getTokenInfo(address token) public view returns (TokenInfo memory) {
        Gauge gauge = Gauge(tokenToGauge[token]);
        if (address(gauge) == address(0)) revert Launchpad__InvalidToken();
        (
            bool active,
            bool closable,
            uint256 tokenPurchased,
            uint256 tokenTarget,
            uint256 totalSupply,
            uint256 ethPaid,
            uint256 currentPrice
        ) = gauge.getGaugeStatistics();
        (uint128 buyFee, uint128 sellFee) = gauge.feeParameters();
        return
            TokenInfo({
                token: token,
                gauge: address(gauge),
                name: LaunchpadToken(token).name(),
                symbol: LaunchpadToken(token).symbol(),
                gaugeActive: active,
                gaugeClosable: closable,
                tokenPurchased: tokenPurchased,
                tokenTarget: tokenTarget,
                totalSupply: totalSupply,
                ethPaid: ethPaid,
                currentPrice: currentPrice,
                buyFee: buyFee,
                sellFee: sellFee,
                metadata: LaunchpadToken(token).getAllMetadata(),
                creator: tokenToCreator[token],
                pool: gauge.pool()
            });
    }

    /**
     * @notice  Get current number of tokens deployed from this launchpad
     * @return  Number of tokens
     */
    function getTokensCount() external view returns (uint256) {
        return tokens.length();
    }

    /**
     * @notice  Get all tokens deployed from this launchpad
     * @return  Array of token addresses
     */
    function getAllTokens() external view returns (address[] memory) {
        return tokens.values();
    }

    /**
     * @notice  Get all tokens deployed from this launchpad and their corresponding gauges
     * @return  Array of token addresses
     * @return  Array of gauge addresses
     */
    function getAllTokensAndGauges() external view returns (address[] memory, address[] memory) {
        address[] memory _tokens = new address[](tokens.length());
        address[] memory _gauges = new address[](tokens.length());
        for (uint256 i; i < tokens.length(); ) {
            address token = tokens.at(i);
            _tokens[i] = token;
            _gauges[i] = tokenToGauge[token];
            unchecked {
                ++i;
            }
        }
        return (_tokens, _gauges);
    }

    /**
     * @notice  Get all tokens deployed from this launchpad and their corresponding information
     * @return  Array of TokenInfo structs
     */
    function getAllTokensInfo() external view returns (TokenInfo[] memory) {
        TokenInfo[] memory data = new TokenInfo[](tokens.length());
        for (uint256 i; i < tokens.length(); ) {
            address token = tokens.at(i);
            data[i] = getTokenInfo(token);
            unchecked {
                ++i;
            }
        }
        return data;
    }

    /**
     * @notice  Get a range of tokens deployed from this launchpad
     * @param   start   Start index
     * @param   end     End index (inclusive)
     * @return  Array of token addresses
     */
    function getTokens(uint256 start, uint256 end) public view returns (address[] memory) {
        if (start > end || end > tokens.length() - 1) revert Launchpad__InvalidIndex();
        address[] memory _tokens = new address[](end - start + 1);
        for (uint256 i = start; i <= end; ) {
            _tokens[i - start] = tokens.at(i);
            unchecked {
                ++i;
            }
        }
        return _tokens;
    }

    /**
     * @notice  Get a range of tokens deployed from this launchpad and their corresponding gauges
     * @param   start   Start index
     * @param   end     End index
     * @return  Array of token addresses
     * @return  Array of gauge addresses
     */
    function getTokensAndGauges(uint256 start, uint256 end) external view returns (address[] memory, address[] memory) {
        address[] memory _tokens = getTokens(start, end);
        address[] memory _gauges = new address[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            _gauges[i] = tokenToGauge[_tokens[i]];
            unchecked {
                ++i;
            }
        }
        return (_tokens, _gauges);
    }

    /**
     * @notice  Get a range of tokens deployed from this launchpad and their corresponding information
     * @param   start   Start index
     * @param   end     End index
     * @return  Array of TokenInfo structs
     */
    function getTokensInfo(uint256 start, uint256 end) external view returns (TokenInfo[] memory) {
        address[] memory _tokens = getTokens(start, end);
        TokenInfo[] memory data = new TokenInfo[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            data[i] = getTokenInfo(_tokens[i]);
            unchecked {
                ++i;
            }
        }
        return data;
    }

    /**
     * @notice  Get `num` most recent tokens deployed from this launchpad
     * @param   num     Number of tokens to return
     * @return  Array of token addresses
     */
    function getMostRecentTokens(uint256 num) public view returns (address[] memory) {
        if (num > tokens.length()) {
            num = tokens.length();
        }
        address[] memory _tokens = new address[](num);
        for (uint256 i; i < num; ) {
            _tokens[i] = tokens.at(tokens.length() - 1 - i);
            unchecked {
                ++i;
            }
        }
        return _tokens;
    }

    /**
     * @notice  Get `num` most recent tokens deployed from this launchpad and their corresponding gauges
     * @param   num     Number of tokens to return
     * @return  Array of token addresses
     * @return  Array of gauge addresses
     */
    function getMostRecentTokensAndGauges(uint256 num) external view returns (address[] memory, address[] memory) {
        if (num > tokens.length()) {
            num = tokens.length();
        }
        address[] memory _tokens = getMostRecentTokens(num);
        address[] memory _gauges = new address[](num);
        for (uint256 i; i < num; ) {
            _gauges[i] = tokenToGauge[_tokens[i]];
            unchecked {
                ++i;
            }
        }
        return (_tokens, _gauges);
    }

    /**
     * @notice  Get `num` most recent tokens deployed from this launchpad and their corresponding information
     * @param   num     Number of tokens to return
     * @return  Array of TokenInfo structs
     */
    function getMostRecentTokensInfo(uint256 num) external view returns (TokenInfo[] memory) {
        if (num > tokens.length()) {
            num = tokens.length();
        }
        address[] memory _tokens = getMostRecentTokens(num);
        TokenInfo[] memory data = new TokenInfo[](num);
        for (uint256 i; i < num; ) {
            data[i] = getTokenInfo(_tokens[i]);
            unchecked {
                ++i;
            }
        }
        return data;
    }

    /**
     * @notice  Get the number of tokens deployed by a creator
     * @param   creator     Creator address
     * @return  Number of tokens
     */
    function getTokensCountByCreator(address creator) external view returns (uint256) {
        return creatorToTokens[creator].length();
    }

    /**
     * @notice  Get all tokens deployed by a creator
     * @param   creator     Creator address
     * @return  Array of token addresses
     */
    function getTokensByCreator(address creator) public view returns (address[] memory) {
        return creatorToTokens[creator].values();
    }

    /**
     * @notice  Get all tokens deployed by a creator and their corresponding gauges
     * @param   creator     Creator address
     * @return  Array of token addresses
     * @return  Array of gauge addresses
     */
    function getTokensAndGaugesByCreator(address creator) external view returns (address[] memory, address[] memory) {
        address[] memory _tokens = getTokensByCreator(creator);
        address[] memory _gauges = new address[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            _gauges[i] = tokenToGauge[_tokens[i]];
            unchecked {
                ++i;
            }
        }
        return (_tokens, _gauges);
    }

    /**
     * @notice  Get all tokens deployed by a creator and their corresponding information
     * @param   creator     Creator address
     * @return  Array of TokenInfo structs
     */
    function getTokensInfoByCreator(address creator) external view returns (TokenInfo[] memory) {
        address[] memory _tokens = getTokensByCreator(creator);
        TokenInfo[] memory data = new TokenInfo[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            data[i] = getTokenInfo(_tokens[i]);
            unchecked {
                ++i;
            }
        }
        return data;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ADMINISTRATION
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Set the token implementation
     * @param   _tokenImplementation    New token implementation address
     */
    function setTokenImplementation(address _tokenImplementation) external onlyOwner {
        if (_tokenImplementation == address(0)) revert Launchpad__ZeroAddress();

        emit TokenImplementationSet(_tokenImplementation, tokenImplementation);
        tokenImplementation = _tokenImplementation;
    }

    /**
     * @notice  Set the gauge implementation
     * @param   _gaugeImplementation    New gauge implementation address
     */
    function setGaugeImplementation(address _gaugeImplementation) external onlyOwner {
        if (_gaugeImplementation == address(0)) revert Launchpad__ZeroAddress();

        emit GaugeImplementationSet(_gaugeImplementation, gaugeImplementation);
        gaugeImplementation = _gaugeImplementation;
    }

    /**
     * @notice  Set a new bonding curve math implementation
     *
     * @param   _bondingcurve  New bonding curve implementation
     */
    function setBondingCurve(address _bondingcurve) external onlyOwner {
        if (_bondingcurve == address(0)) revert Launchpad__ZeroAddress();

        emit CurveSet(_bondingcurve, bondingcurve);
        bondingcurve = _bondingcurve;
    }

    /**
     * @notice  Set the treasury address
     * @param   _treasury   The new treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Launchpad__ZeroAddress();

        emit TreasurySet(_treasury, treasury);
        treasury = _treasury;
    }

    /**
     * @notice  Set the LP receiver address
     * @param   _lpReceiver     The new LP receiver address
     */
    function setLpReceiver(address _lpReceiver) external onlyOwner {
        if (_lpReceiver == address(0)) revert Launchpad__ZeroAddress();

        emit LpReceiverSet(_lpReceiver, lpReceiver);
        lpReceiver = _lpReceiver;
    }

    /**
     * @notice  Set the creation cost
     * @param   _creationCost   The new creation cost
     */
    function setCreationCost(uint256 _creationCost) external onlyOwner {
        if (_creationCost > MAX_CREATION_COST) revert Launchpad__ExcessiveCreationCost();

        emit CreationCostSet(_creationCost, creationCost);
        creationCost = _creationCost;
    }

    /**
     * @notice Set the gauge fees
     *         Gauge fees are charged when users buy tokens from bonding curve
     *
     * @param _gaugeFees The new gauge fees
     */
    function setGaugeFees(Gauge.FeeParameters calldata _gaugeFees) external onlyOwner {
        if (_gaugeFees.buyFee > MAX_GAUGE_FEE || _gaugeFees.sellFee > MAX_GAUGE_FEE) {
            revert Launchpad__ExcessiveGaugeFee();
        }

        emit GaugeFeesSet(_gaugeFees.buyFee, gaugeFees.buyFee, _gaugeFees.sellFee, gaugeFees.sellFee);
        gaugeFees = _gaugeFees;
    }
}
