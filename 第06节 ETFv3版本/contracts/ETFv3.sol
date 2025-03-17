// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ETFv2} from "./ETFv2.sol";
import {IETFv3} from "./interfaces/IETFv3.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IETFQuoter} from "./interfaces/IETFQuoter.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@5.1.0/interfaces/IERC20Metadata.sol";
import {IV3SwapRouter} from "./interfaces/IV3SwapRouter.sol";

contract ETFv3 is IETFv3, ETFv2 {//继承V3，V2版本
    using FullMath for uint256;//使用library的FullMath

    address public etfQuoter;

    uint256 public lastRebalanceTime;
    uint256 public rebalanceInterval;
    uint24 public rebalanceDeviance;

    mapping(address token => address priceFeed) public getPriceFeed;//mapping存储了每个token的priceFeed
    mapping(address token => uint24 targetWeight) public getTokenTargetWeight;//存储了每个token的目标权重

    modifier _checkTotalWeights() {//modifier，函数修改器，用于检查？
        address[] memory tokens = getTokens();//地址数组，存放每个token的地址？
        uint24 totalWeights;//总权重值
        for (uint256 i = 0; i < tokens.length; i++) {//每个代币的权重值，遍历相加
            totalWeights += getTokenTargetWeight[tokens[i]];//相加
        }
        if (totalWeights != HUNDRED_PERCENT) revert InvalidTotalWeights();//总权重值必须等于百分百，否则报错

        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory tokens_,
        uint256[] memory initTokenAmountPerShare_,
        uint256 minMintAmount_,
        address swapRouter_,
        address weth_,
        address etfQuoter_
    )
        ETFv2(
            name_,
            symbol_,
            tokens_,
            initTokenAmountPerShare_,
            minMintAmount_,
            swapRouter_,
            weth_
        )
    {
        etfQuoter = etfQuoter_;
    }

    function setPriceFeeds(
        address[] memory tokens,
        address[] memory priceFeeds
    ) external onlyOwner {
        if (tokens.length != priceFeeds.length) revert DifferentArrayLength();
        for (uint256 i = 0; i < tokens.length; i++) {
            getPriceFeed[tokens[i]] = priceFeeds[i];
        }
    }

    function setTokenTargetWeights(
        address[] memory tokens,
        uint24[] memory targetWeights
    ) external onlyOwner {
        if (tokens.length != targetWeights.length) revert InvalidArrayLength();
        for (uint256 i = 0; i < targetWeights.length; i++) {
            getTokenTargetWeight[tokens[i]] = targetWeights[i];
        }
    }

    function updateRebalanceInterval(uint256 newInterval) external onlyOwner {
        rebalanceInterval = newInterval;
    }

    function updateRebalanceDeviance(uint24 newDeviance) external onlyOwner {
        rebalanceDeviance = newDeviance;
    }

    function addToken(address token) external onlyOwner {
        _addToken(token);
    }

    function removeToken(address token) external onlyOwner {
        if (
            IERC20(token).balanceOf(address(this)) > 0 ||
            getTokenTargetWeight[token] > 0
        ) revert Forbidden();
        _removeToken(token);
    }

    function rebalance() external _checkTotalWeights {
        // 当前是否到了允许rebalance的时间
        if (block.timestamp < lastRebalanceTime + rebalanceInterval)
            revert NotRebalanceTime();
        lastRebalanceTime = block.timestamp;

        // 计算出每个币的市值和总市值
        (
            address[] memory tokens,
            int256[] memory tokenPrices,
            uint256[] memory tokenMarketValues,
            uint256 totalValues
        ) = getTokenMarketValues();

        // 计算每个币需要rebalance进行swap的数量
        int256[] memory tokenSwapableAmounts = new int256[](tokens.length);
        uint256[] memory reservesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            reservesBefore[i] = IERC20(tokens[i]).balanceOf(address(this));

            if (getTokenTargetWeight[tokens[i]] == 0) continue;

            uint256 weightedValue = (totalValues *
                getTokenTargetWeight[tokens[i]]) / HUNDRED_PERCENT;
            uint256 lowerValue = (weightedValue *
                (HUNDRED_PERCENT - rebalanceDeviance)) / HUNDRED_PERCENT;
            uint256 upperValue = (weightedValue *
                (HUNDRED_PERCENT + rebalanceDeviance)) / HUNDRED_PERCENT;
            if (
                tokenMarketValues[i] < lowerValue ||
                tokenMarketValues[i] > upperValue
            ) {
                int256 deltaValue = int256(weightedValue) -
                    int256(tokenMarketValues[i]);
                uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();

                if (deltaValue > 0) {
                    tokenSwapableAmounts[i] = int256(
                        uint256(deltaValue).mulDiv(
                            10 ** tokenDecimals,
                            uint256(tokenPrices[i])
                        )
                    );
                } else {
                    tokenSwapableAmounts[i] = -int256(
                        uint256(-deltaValue).mulDiv(
                            10 ** tokenDecimals,
                            uint256(tokenPrices[i])
                        )
                    );
                }
            }
        }

        _swapTokens(tokens, tokenSwapableAmounts);

        uint256[] memory reservesAfter = new uint256[](tokens.length);
        for (uint256 i = 0; i < reservesAfter.length; i++) {
            reservesAfter[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        emit Rebalanced(reservesBefore, reservesAfter);
    }

    function getTokenMarketValues()
        public
        view
        returns (
            address[] memory tokens,
            int256[] memory tokenPrices,
            uint256[] memory tokenMarketValues,
            uint256 totalValues
        )
    {
        tokens = getTokens();
        uint256 length = tokens.length;
        tokenPrices = new int256[](length);
        tokenMarketValues = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(
                getPriceFeed[tokens[i]]
            );
            if (address(priceFeed) == address(0))
                revert PriceFeedNotFound(tokens[i]);
            (, tokenPrices[i], , , ) = priceFeed.latestRoundData();

            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            uint256 reserve = IERC20(tokens[i]).balanceOf(address(this));
            tokenMarketValues[i] = reserve.mulDiv(
                uint256(tokenPrices[i]),
                10 ** tokenDecimals
            );
            totalValues += tokenMarketValues[i];
        }
    }

    function _swapTokens(
        address[] memory tokens,
        int256[] memory tokenSwapableAmounts
    ) internal {
        address usdc = IETFQuoter(etfQuoter).usdc();
        // 第一步：先进行所有的卖出操作，确保有足够的USDC余额
        uint256 usdcRemaining = _sellTokens(usdc, tokens, tokenSwapableAmounts);
        // 第二步：进行所有的买入操作
        usdcRemaining = _buyTokens(
            usdc,
            tokens,
            tokenSwapableAmounts,
            usdcRemaining
        );
        // 如果usdc依然还有余存，按权重比例分配买入每个代币
        if (usdcRemaining > 0) {
            uint256 usdcLeft = usdcRemaining;
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 amountIn = (usdcRemaining *
                    getTokenTargetWeight[tokens[i]]) / HUNDRED_PERCENT;
                if (amountIn == 0) continue;
                if (amountIn > usdcLeft) {
                    amountIn = usdcLeft;
                }
                (bytes memory path, ) = IETFQuoter(etfQuoter).quoteExactIn(
                    usdc,
                    tokens[i],
                    amountIn
                );
                IV3SwapRouter(swapRouter).exactInput(
                    IV3SwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        amountIn: amountIn,
                        amountOutMinimum: 1
                    })
                );
                usdcLeft -= amountIn;
                if (usdcLeft == 0) break;
            }
        }
    }

    function _sellTokens(
        address usdc,
        address[] memory tokens,
        int256[] memory tokenSwapableAmounts
    ) internal returns (uint256 usdcRemaining) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenSwapableAmounts[i] < 0) {
                uint256 amountIn = uint256(-tokenSwapableAmounts[i]);
                (bytes memory path, ) = IETFQuoter(etfQuoter).quoteExactIn(
                    tokens[i],
                    usdc,
                    amountIn
                );
                _approveToSwapRouter(tokens[i]);
                usdcRemaining += IV3SwapRouter(swapRouter).exactInput(
                    IV3SwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),
                        amountIn: amountIn,
                        amountOutMinimum: 1
                    })
                );
            }
        }
    }

    function _buyTokens(
        address usdc,
        address[] memory tokens,
        int256[] memory tokenSwapableAmounts,
        uint256 usdcRemaining
    ) internal returns (uint256 usdcLeft) {
        usdcLeft = usdcRemaining;
        _approveToSwapRouter(usdc);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenSwapableAmounts[i] > 0) {
                (bytes memory path, uint256 amountIn) = IETFQuoter(etfQuoter)
                    .quoteExactOut(
                        usdc,
                        tokens[i],
                        uint256(tokenSwapableAmounts[i])
                    );
                if (usdcLeft >= amountIn) {
                    usdcLeft -= IV3SwapRouter(swapRouter).exactOutput(
                        IV3SwapRouter.ExactOutputParams({
                            path: path,
                            recipient: address(this),
                            amountOut: uint256(tokenSwapableAmounts[i]),
                            amountInMaximum: type(uint256).max
                        })
                    );
                } else if (usdcLeft > 0) {
                    (path, ) = IETFQuoter(etfQuoter).quoteExactIn(
                        usdc,
                        tokens[i],
                        usdcLeft
                    );
                    IV3SwapRouter(swapRouter).exactInput(
                        IV3SwapRouter.ExactInputParams({
                            path: path,
                            recipient: address(this),
                            amountIn: usdcLeft,
                            amountOutMinimum: 1
                        })
                    );
                    usdcLeft = 0;
                    break;
                }
            }
        }
    }
}
