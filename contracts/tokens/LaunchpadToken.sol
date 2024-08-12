// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import { Gauge } from "./Gauge.sol";


/**
 * --------------------------------------------------------------------------------
 *
 * @title   LaunchpadToken

 * @notice  ERC20 token with transfer restricted when a linked Gauge is active
 *          Compatible with OpenZeppelin Contracts ^5.0.0
 *          Intended for minimal proxy cloning
 *
 * --------------------------------------------------------------------------------
 */
contract LaunchpadToken is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////
    // STATE
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Address of the Gauge responsible for managing the token
    Gauge public gauge;
    /// @notice Address of the router allowed to transfer tokens while the Gauge is active
    address public router;

    /// @notice Token image IPFS hash
    string public ipfsHash;
    /// @notice Project website
    string public website;
    /// @notice Project Twitter handle
    string public twitter;
    /// @notice Project Telegram link
    string public telegram;
    /// @notice Description of the token
    string public description;
    /// @notice Assorted metadata for the token
    string public metadata;

    ////////////////////////////////////////////////////////////////////////////////
    // CONSTRUCTION AND INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    constructor() {
        _disableInitializers();
    }

    // Configuration for launching a new token
    struct TokenConfig {
        string name;
        string symbol;
        uint256 initialSupply;
    }

    struct TokenMetadataConfig {
        string ipfsHash;
        string website;
        string twitter;
        string telegram;
        string description;
        string metadata;
    }

    function initialize(TokenConfig memory _tokenConfig, TokenMetadataConfig memory _metadataConfig, address _gauge) external initializer {
        __ERC20_init(_tokenConfig.name, _tokenConfig.symbol);
        __ERC20Permit_init(_tokenConfig.name);

        if (_gauge == address(0)) revert LaunchpadToken__ZeroAddress();
        gauge = Gauge(_gauge);
        router = msg.sender;

        ipfsHash = _metadataConfig.ipfsHash;
        website = _metadataConfig.website;
        twitter = _metadataConfig.twitter;
        telegram = _metadataConfig.telegram;
        description = _metadataConfig.description;
        metadata = _metadataConfig.metadata;

        _mint(msg.sender, _tokenConfig.initialSupply);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // OVERRIDES
    ////////////////////////////////////////////////////////////////////////////////

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (gauge.gaugeActive()) {
            if (msg.sender != address(gauge) && msg.sender != router) revert LaunchpadToken__TransferForbidden();
        }
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (gauge.gaugeActive()) {
            if (msg.sender != address(gauge) && msg.sender != router) revert LaunchpadToken__TransferForbidden();
        }
        return super.transferFrom(sender, recipient, amount);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // METADATA
    ////////////////////////////////////////////////////////////////////////////////

    function getAllMetadata() external view returns (TokenMetadataConfig memory) {
        return
            TokenMetadataConfig({
                ipfsHash: ipfsHash,
                website: website,
                twitter: twitter,
                telegram: telegram,
                description: description,
                metadata: metadata
            });
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////////

    error LaunchpadToken__ZeroAddress();
    error LaunchpadToken__TransferForbidden();
}