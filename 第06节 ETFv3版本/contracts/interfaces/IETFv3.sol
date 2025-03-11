// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IETFv2} from "./IETFv2.sol";

interface IETFv3 is IETFv2 {
    error DifferentArrayLength();
    error NotRebalanceTime();
    error InvalidTotalWeights();
    error Forbidden();
    error PriceFeedNotFound(address token);

    event Rebalanced(uint256[] reservesBefore, uint256[] reservesAfter);

    function rebalance() external;//设置rebalance，定期重置权重；把市场市值调整成为目标市值，把过高价格的token卖出，过低价格的买入，重新恢复权重

    function setPriceFeeds(
        address[] memory tokens,
        address[] memory priceFeeds
    ) external;

    function setTokenTargetWeights(
        address[] memory tokens,
        uint24[] memory targetWeights
    ) external;

    function updateRebalanceInterval(uint256 newInterval) external;

    function updateRebalanceDeviance(uint24 newDeviance) external;

    function addToken(address token) external;

    function removeToken(address token) external;

    function lastRebalanceTime() external view returns (uint256);

    function rebalanceInterval() external view returns (uint256);

    function rebalanceDeviance() external view returns (uint24);

    function getPriceFeed(
        address token
    ) external view returns (address priceFeed);

    function getTokenTargetWeight(
        address token
    ) external view returns (uint24 targetWeight);

    function getTokenMarketValues()
        external
        view
        returns (
            address[] memory tokens,
            int256[] memory tokenPrices,
            uint256[] memory tokenMarketValues,
            uint256 totalValues
        );
}
