// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721, ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Beranouns (🐻/🐻).bera
 * @author Beranouns Inc.
 * @notice ERC721 compliant contract managing Beranouns NFTs.
 * The contract is minimalistic by design and its logic is limited to what is strictly necessary for storing data and integrating with other contracts.
 * Any action that can be delegated off-chain is not included.
 */
contract Beranouns is Ownable, Pausable, ERC721Enumerable {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    event SetAKA(uint256 id, address aka);
    event SetURI(uint256 id, string uri);
    event Extended(uint256 id, uint256 extension);
    event SetFeesCollector(address newCollector);

    Counters.Counter internal _id;
    mapping(uint256 => bytes32) public nouns; // 1 => keccak256(abi.encode(🐻), abi.encode(🐻))
    mapping(bytes32 => uint256) public nounToId; // keccak256(abi.encode(🐻), abi.encode(🐻)) => 1
    mapping(bytes32 => uint256) public expiry;
    mapping(bytes32 => address) public aka;
    mapping(uint256 => string) public URI; // uri containing json metadata
    // pricing
    mapping(bytes32 => uint256) public yearlyPrice; // keccak256(abi.encode(🐻), abi.encode(🐻)) => 660 * 1e18
    mapping(bytes32 => uint256) public componentYearlyPrice; // 🐻 => 330 * 1e18

    // CONFIG
    address public feesCollector;

    constructor(
        string memory name_,
        string memory symbol_,
        address feesCollector_
    ) ERC721(name_, symbol_) {
        feesCollector = feesCollector_;
    }

    /**
     * @notice Create hash from beranoun components
     * @param token0 - first component of beranoun
     * @param token1 - second component of beranoun
     * @return noun - the bytes32 hash resulting from the inputs
     */
    function getHash(bytes32 token0, bytes32 token1)
        public
        pure
        returns (bytes32 noun)
    {
        noun = keccak256(abi.encode(token0, token1));
    }

    /**
     * @notice Set the AKA for the beranoun with  #`id`
     */
    function setAKA(uint256 id, address aka_) external {
        require(ownerOf(id) == _msgSender(), "NOT_OWNER");
        aka[nouns[id]] = aka_;
        emit SetAKA(id, aka_);
    }

    /**
     * @notice Update metadata for noun `id` to be `uri_`
     * The owner is free to set whichever uri for their beranoun
     */
    function setTokenUri(uint256 id, string calldata uri_) external {
        require(ownerOf(id) == _msgSender(), "NOT_OWNER");
        URI[id] = uri_;
        emit SetURI(id, uri_);
    }

    /**
     * @inheritdoc ERC721
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireMinted(id);
        return URI[id];
    }

    /**
     * @notice Mint (`token0`/`token1`).bera
     * @dev Requires approval of $HONEY
     * @param token0 - first component of the noun
     * @param token1 - second component of the noun
     * @param duration - length of lease in years
     * @param aka_ - alias to which the noun points to
     * @param to - the owner of the noun
     */
    function mint(
        string calldata token0,
        string calldata token1,
        uint256 duration,
        address aka_,
        address to
    ) external whenNotPaused {
        require(duration > 0, "INVALID_LEASE_LENGTH");

        bytes32 t0 = keccak256(abi.encode(token0));
        bytes32 t1 = keccak256(abi.encode(token1));
        bytes32 noun = keccak256(abi.encode(t0, t1));
        require(nounToId[noun] == 0, "ALREADY_EXISTS");

        uint256 price0 = componentYearlyPrice[t0];
        if (price0 == 0) {
            price0 = price(token0);
            componentYearlyPrice[t0] = price0;
        }
        uint256 price1 = componentYearlyPrice[t1];
        if (price1 == 0) {
            price1 = price(token1);
            componentYearlyPrice[t1] = price1;
        }
        yearlyPrice[noun] = (price0 + price1);

        _id.increment(); // no token can have id = 0;
        uint256 currentId = _id.current();

        _safeMint(to, currentId);
        nouns[currentId] = noun;
        aka[noun] = aka_;
        expiry[noun] = block.timestamp + duration * 365 days;

        IERC20 paymentAsset = IERC20(address(1)); // TODO - set address of $HONEY
        paymentAsset.safeTransferFrom(
            _msgSender(),
            feesCollector,
            (price0 + price1) * duration
        );
    }

    /**
     * @notice Buy the beranoun with id `id`
     * This function can only be called for nouns that already exist
     * @param id - the id of the noun to buy
     * @param duration - the length in years of the lease
     * @param aka_ - the address the noun points to
     * @param to - the new owner of the noun
     */
    function buy(
        uint256 id,
        uint256 duration,
        address aka_,
        address to
    ) external whenNotPaused {
        IERC20 paymentAsset = IERC20(address(1)); // TODO - set address of $HONEY
        bytes32 noun = nouns[id];
        paymentAsset.safeTransferFrom(
            _msgSender(),
            feesCollector,
            yearlyPrice[noun] * duration
        );

        _safeMint(to, id); // already checks if owner is address(0)
        expiry[noun] = block.timestamp + (duration * 365 days);
        aka[noun] = aka_;
    }

    /**
     * @notice Extend the lease of Beranoun with id `id` for another `extension` years
     * @param id - the id of the beranoun
     * @param duration - the amount of years to extend the lease for
     */
    function extend(uint256 id, uint256 duration) external {
        _requireMinted(id);
        bytes32 noun = nouns[id];
        // extend can only be called on minted nouns, so yearlyPrice[id] is set
        uint256 amount = yearlyPrice[noun] * duration;
        IERC20 paymentAsset = IERC20(address(1)); // TODO - set address of $HONEY
        paymentAsset.safeTransferFrom(_msgSender(), feesCollector, amount);
        expiry[noun] += duration * 365 days;
        emit Extended(id, duration);
    }

    /**
     * @notice Burn the beranoun with id `id`
     * @dev Anyone can burn this beranoun as it can only be burned after expiry
     */
    function burn(uint256 id) external {
        require(block.timestamp >= expiry[nouns[id]], "NOT_EXPIRED");
        _burn(id); // among other things sets address(0) as owner
    }

    /**
     * @notice Calculate price for using `token` within a noun
     * @param token - string of the noun component
     * @return amount - the amount of $HONEY required
     */
    function price(string memory token) public returns (uint256) {
        uint256 length = bytes(token).length;
        bytes32 tkn = keccak256(abi.encode(token));
        if (componentYearlyPrice[tkn] != 0) {
            return componentYearlyPrice[tkn];
        }
        uint256 amount;
        if (length == 1) {
            amount = 300;
        } else if (length == 2) {
            amount = 200;
        } else if (length == 3) {
            amount = 150;
        } else if (length == 4) {
            amount = 80;
        } else if (4 < length && length < 10) {
            amount = 100 - (10 * length);
        } else {
            amount = 5;
        }
        amount *= 1e18; // TODO - check $HONEY actually has 18 decimals
        componentYearlyPrice[tkn] = amount;
        return amount;
    }

    // ADMIN FUNCTIONS
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFeesCollector(address newCollector) external onlyOwner {
        feesCollector = newCollector;
        emit SetFeesCollector(newCollector);
    }

    /**
     * @notice Set prices for specific components
     * @param components - a list of keccak256(abi.encode(<component>))
     * @param prices - a list of prices
     */
    function setComponentYearlyPrice(
        bytes32[] calldata components,
        uint256[] calldata prices
    ) external onlyOwner {
        uint256 length = components.length;
        for (uint256 i; i < length; ++i) {
            componentYearlyPrice[components[i]] = prices[i];
        }
    }
}
