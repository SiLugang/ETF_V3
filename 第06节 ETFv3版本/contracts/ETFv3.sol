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

    constructor(//初始化变量
        string memory name_,//名称
        string memory symbol_,//符号
        address[] memory tokens_,//tokens
        uint256[] memory initTokenAmountPerShare_,//初始化每份份额
        uint256 minMintAmount_,//最小mint
        address swapRouter_,//swapRouter
        address weth_,//weth地址
        address etfQuoter_//相比V2多了一个etfQuoter_
    )
        ETFv2(//为什么这里又有一个ETFv2，什么用？
            name_,
            symbol_,
            tokens_,
            initTokenAmountPerShare_,
            minMintAmount_,
            swapRouter_,
            weth_
        )
    {
        etfQuoter = etfQuoter_;//etfQuoter初始化
    }

    function setPriceFeeds(//喂价
        address[] memory tokens,//代币地址
        address[] memory priceFeeds//代币喂价
    ) external onlyOwner {//外部仅有owner可以调用
        if (tokens.length != priceFeeds.length) revert DifferentArrayLength();//前面两个数组长度不一致则报错
        for (uint256 i = 0; i < tokens.length; i++) {//遍历，预言机获得的价格赋值
            getPriceFeed[tokens[i]] = priceFeeds[i];
        }
    }

    function setTokenTargetWeights(//设置目标权重
        address[] memory tokens,//token地址的数组
        uint24[] memory targetWeights//token的权重
    ) external onlyOwner {//外部可见，只有owner有权限
        if (tokens.length != targetWeights.length) revert InvalidArrayLength();//判断两数组长度相等，否则报错
        for (uint256 i = 0; i < targetWeights.length; i++) {//遍历，将目标权重赋值给targetweight
            getTokenTargetWeight[tokens[i]] = targetWeights[i];
        }
    }

    function updateRebalanceInterval(uint256 newInterval) external onlyOwner {//owner权限设置更新rebalance间隔
        rebalanceInterval = newInterval;
    }

    function updateRebalanceDeviance(uint24 newDeviance) external onlyOwner {//owner权限设置rebalance偏差度
        rebalanceDeviance = newDeviance;
    }

    function addToken(address token) external onlyOwner {//增加token
        _addToken(token);
    }

    function removeToken(address token) external onlyOwner {//删除token
        if (
            IERC20(token).balanceOf(address(this)) > 0 ||//有该删除的token余额不为零的情况下，返回报错
            getTokenTargetWeight[token] > 0//且targetWeigth不能大于0
        ) revert Forbidden();//报错
        _removeToken(token);//其他情况下remove
    }

    function rebalance() external _checkTotalWeights {//检查权重是否为百分百
        // 当前是否到了允许rebalance的时间
        if (block.timestamp < lastRebalanceTime + rebalanceInterval)//判断是否到达rebalance时间，当前时间必须大于上次rebalance时间+rebalance间隔
            revert NotRebalanceTime();//返回报错
        lastRebalanceTime = block.timestamp;//将当前时间戳赋值给上次rebalance时间

        // 计算出每个币的市值和总市值
        (
            address[] memory tokens,
            int256[] memory tokenPrices,
            uint256[] memory tokenMarketValues,
            uint256 totalValues
        ) = getTokenMarketValues();//这是什么格式？把等号右边赋值给左边？

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

    function getTokenMarketValues()//获得市值
        public
        view
        returns (
            address[] memory tokens,
            int256[] memory tokenPrices,
            uint256[] memory tokenMarketValues,
            uint256 totalValues
        )
    {
        tokens = getTokens();//tokens列表
        uint256 length = tokens.length;
        tokenPrices = new int256[](length);//初始化tokenPrice
        tokenMarketValues = new uint256[](length);//初始化marketValue
        for (uint256 i = 0; i < length; i++) {//遍历
            AggregatorV3Interface priceFeed = AggregatorV3Interface(//chianlink提供的接口
                getPriceFeed[tokens[i]]//取出pricefeed
            );
            if (address(priceFeed) == address(0))//如果该地址为0地址，则报错。
                revert PriceFeedNotFound(tokens[i]);//报错
            (, tokenPrices[i], , , ) = priceFeed.latestRoundData();//获得价格

            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();//该代币的精度拿出来
            uint256 reserve = IERC20(tokens[i]).balanceOf(address(this));//该代币在池子中的储备量
            tokenMarketValues[i] = reserve.mulDiv(//reserve*该price
                uint256(tokenPrices[i]),//int256的转换为uint256，做运算
                10 ** tokenDecimals//统一精度？
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
