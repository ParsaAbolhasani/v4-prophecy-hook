// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @title MockPyth
/// @notice Mock Pyth oracle for local testing
/// @dev Allows setting price, confidence, and timestamp
contract MockPyth is IPyth {
    struct PriceData {
        int64 price;
        uint64 conf;
        int32 expo;
        uint64 publishTime;
    }

    mapping(bytes32 => PriceData) private _prices;

    /// @notice Set a mock price for a feed
    function setPrice(
        bytes32 id,
        int64 price,
        uint64 conf,
        int32 expo,
        uint64 publishTime
    ) external {
        _prices[id] = PriceData({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: publishTime
        });
    }

    /// @notice Set price with default expo (-8) and current timestamp
    function setPriceSimple(bytes32 id, int64 price) external {
        _prices[id] = PriceData({
            price: price,
            conf: 0,
            expo: -8,
            publishTime: uint64(block.timestamp)
        });
    }

    /// @notice Set price with confidence interval
    function setPriceWithConfidence(
        bytes32 id,
        int64 price,
        uint64 conf
    ) external {
        _prices[id] = PriceData({
            price: price,
            conf: conf,
            expo: -8,
            publishTime: uint64(block.timestamp)
        });
    }

    // ─── IPyth Implementation ──────────────────────────────────────

    function getPriceUnsafe(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        PriceData memory data = _prices[id];
        return PythStructs.Price({
            price: data.price,
            conf: data.conf,
            expo: data.expo,
            publishTime: data.publishTime
        });
    }

    function getPrice(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        PriceData memory data = _prices[id];
        return PythStructs.Price({
            price: data.price,
            conf: data.conf,
            expo: data.expo,
            publishTime: data.publishTime
        });
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        PriceData memory data = _prices[id];
        require(
            block.timestamp - data.publishTime <= age,
            "price too old"
        );
        return PythStructs.Price({
            price: data.price,
            conf: data.conf,
            expo: data.expo,
            publishTime: data.publishTime
        });
    }

    function getEmaPriceUnsafe(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPriceUnsafe(id);
    }

    function getEmaPrice(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPrice(id);
    }

    function getEmaPriceNoOlderThan(bytes32 id, uint256 age)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPriceNoOlderThan(id, age);
    }

    function getUpdateFee(bytes[] calldata)
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata)
        external
        payable
        override
    {}

    function updatePriceFeedsIfNecessary(
        bytes[] calldata,
        bytes32[] calldata,
        uint64[] calldata
    ) external payable override {}

    function getTwapPriceUnsafe(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPriceUnsafe(id);
    }

    function getTwapPrice(bytes32 id)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPrice(id);
    }

    function getTwapPriceNoOlderThan(bytes32 id, uint256 age)
        external
        view
        override
        returns (PythStructs.Price memory price)
    {
        return this.getPriceNoOlderThan(id, age);
    }

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable override {}
}
