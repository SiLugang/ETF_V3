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

    function rebalance() external;//设置rebalance，定期重置权重；把市场市值调整成为目标市值，把过高价格的token卖出，过低价格的买入，重新恢复权重。以价格占比为准。

    function setPriceFeeds(//使用chainlink的预言机，获取代币的最新价格
        address[] memory tokens,//代币
        address[] memory priceFeeds//代币价格feed
    ) external;

    function setTokenTargetWeights(//代币权重
        address[] memory tokens,//代币
        uint24[] memory targetWeights//代币目标权重
    ) external;

    function updateRebalanceInterval(uint256 newInterval) external;//更新rebalance时间间隔，由于滑点损耗和手续费，过于频繁的rebalance会让池子里的代币慢慢减少

    function updateRebalanceDeviance(uint24 newDeviance) external;//代币的实际价值权重和target_weigth偏离多少时，才需要rebalance

    function addToken(address token) external;//更新代币列表：增加代币

    function removeToken(address token) external;//：删除代币

    function lastRebalanceTime() external view returns (uint256);//记录上次rebalance时间，该时间加上rebalance间隔等于下次rebalance时间

    function rebalanceInterval() external view returns (uint256);//rebalance间隔

    function rebalanceDeviance() external view returns (uint24);//rebalance

    function getPriceFeed(//从预言机获取价格
        address token
    ) external view returns (address priceFeed);//返回地址？

    function getTokenTargetWeight(//获得代币的目标权重
        address token
    ) external view returns (uint24 targetWeight);//24位无符号整数的权重值

    function getTokenMarketValues()//每个代币的市场价格
        external
        view
        returns (
            address[] memory tokens,//代币地址
            int256[] memory tokenPrices,//代币价格
            uint256[] memory tokenMarketValues,//代币市场价格？
            uint256 totalValues//市值总价（TVL）
        );
}
