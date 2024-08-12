// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BoosterTreasury is OwnableUpgradeable, EIP712Upgradeable {
    using ECDSA for bytes32;

    // EIP712 related variables
    // When updating the contract, directly update these constants
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant HASHED_NAME = keccak256(bytes("BoosterTreasury"));
    bytes32 public constant HASHED_VERSION = keccak256(bytes("1.0"));

    struct AirdropRequest {
        address user; // User address
        address token; // Token address
        uint256 amount; // Amount of tokens to be distributed
        uint256 validUntil; // Signature is valid until this timestamp
    }
    bytes32 public constant AIRDROP_REQUEST_TYPEHASH =
        keccak256("AirdropRequest(address user,address token,uint256 amount,uint256 validUntil)");

    mapping(address signer => bool isValid) public isValidSigner;

    mapping(address user => mapping(address token => bool alreadyClaimed)) public claimed;

    struct AirdropInfo {
        address token;
        uint256 amount;
        uint256 alreadyClaimedAmount;
    }
    mapping(address token => AirdropInfo info) public airdrops;
    address public launchpad;

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event AirdropClaimed(address indexed user, address indexed token, uint256 amount);
    event AirdropReceived(address indexed token, uint256 amount);

    error OnlyLaunchpad();
    error InvalidSigner();
    error SignatureExpired();
    error InvalidToken();
    error AlreadyClaimed();
    error AirdropAllClaimed();  

    constructor() {
        _disableInitializers();
    }
    
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __EIP712_init("BoosterTreasury", "1.0");

        isValidSigner[msg.sender] = true;
    }

    function getDomainSeparatorV4() public view returns (bytes32) {
        // domainSeparator = keccak256(
        //     abi.encode(EIP712_DOMAIN_TYPEHASH, HASHED_NAME, HASHED_VERSION, block.chainid, address(this))
        // );
        return super._domainSeparatorV4();
    }

    function getStructHash(AirdropRequest memory _request) public pure returns (bytes32 structHash) {
        structHash = keccak256(
            abi.encode(AIRDROP_REQUEST_TYPEHASH, _request.user, _request.token, _request.amount, _request.validUntil)
        );
    }

    function addSigner(address _signer) external onlyOwner {
        isValidSigner[_signer] = true;
        emit SignerAdded(_signer);
    }

    function removeSigner(address _signer) external onlyOwner {
        isValidSigner[_signer] = false;
        emit SignerRemoved(_signer);
    }

    function setLaunchpad(address _launchpad) external onlyOwner {
        launchpad = _launchpad;
    }

    function receiveAirdrop(address _token, uint256 _amount) external {
        if (msg.sender != launchpad) revert OnlyLaunchpad();

        airdrops[_token].token = _token;
        airdrops[_token].amount = _amount;

        emit AirdropReceived(_token, _amount);
    }

    function requestAirdrop(address _token, uint256 _amount, uint256 _validUntil, bytes calldata _signature) external {
        if (_validUntil < block.timestamp) revert SignatureExpired();
        if (_token == address(0)) revert InvalidToken();
        if (claimed[msg.sender][_token]) revert AlreadyClaimed();
        if (airdrops[_token].alreadyClaimedAmount + _amount > airdrops[_token].amount) revert AirdropAllClaimed();

        _checkEIP712Signature(msg.sender, _token, _amount, _validUntil, _signature);

        airdrops[_token].alreadyClaimedAmount += _amount;

        claimed[msg.sender][_token] = true;
        IERC20(_token).transfer(msg.sender, _amount);

        emit AirdropClaimed(msg.sender, _token, _amount);
    }

    function _checkEIP712Signature(
        address _user,
        address _token,
        uint256 _amount,
        uint256 _validUntil,
        bytes calldata _signature
    ) public view {
        AirdropRequest memory req = AirdropRequest({
            user: _user,
            token: _token,
            amount: _amount,
            validUntil: _validUntil
        });

        bytes32 digest = super._hashTypedDataV4(getStructHash(req));
        // bytes32 digest = getDomainSeparatorV4().toTypedDataHash(getStructHash(req));

        address recoveredAddress = digest.recover(_signature);
        if (!isValidSigner[recoveredAddress]) revert InvalidSigner();
    }

    function retrieve() external onlyOwner {
        // Retrieve funds from the treasury
        payable(owner()).transfer(address(this).balance);
    }

    function retrieveERC20(address _token) external onlyOwner {
        // Retrieve ERC20 tokens from the treasury
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
    }

    receive() external payable {}
    fallback() external payable {}
}
