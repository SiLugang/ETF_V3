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

        // 计算每个币需要rebalance进行swap的数量-----计算每种代币应该买多少，卖多少
        int256[] memory tokenSwapableAmounts = new int256[](tokens.length);//要进行swap的数量
        uint256[] memory reservesBefore = new uint256[](tokens.length);//每个代币在互换之前的储备量是多少
        for (uint256 i = 0; i < tokens.length; i++) {//遍历
            reservesBefore[i] = IERC20(tokens[i]).balanceOf(address(this));//读出每个代币的余额

            if (getTokenTargetWeight[tokens[i]] == 0) continue;//目标权重等于0，则跳过

            uint256 weightedValue = (totalValues *
                getTokenTargetWeight[tokens[i]]) / HUNDRED_PERCENT;//算出权重value
            uint256 lowerValue = (weightedValue *
                (HUNDRED_PERCENT - rebalanceDeviance)) / HUNDRED_PERCENT;//下限value=权重*（100%+浮动值）/100%
            uint256 upperValue = (weightedValue *
                (HUNDRED_PERCENT + rebalanceDeviance)) / HUNDRED_PERCENT;//上限value=权重*（100%+浮动值）/100%
            if (
                tokenMarketValues[i] < lowerValue ||//在这个区间以外的values值，触发rebalance
                tokenMarketValues[i] > upperValue
            ) {
                int256 deltaValue = int256(weightedValue) -
                    int256(tokenMarketValues[i]);//deltaValue什么意思？----------正数或者负数，正数代表权重值大于市值，需要买入，复数代表权重值小于市值，需要卖出。
                uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();//精度值赋值

                if (deltaValue > 0) {//大于0时，正数代表权重值大于市值，需要买入
                    tokenSwapableAmounts[i] = int256(
                        uint256(deltaValue).mulDiv(
                            10 ** tokenDecimals,
                            uint256(tokenPrices[i])
                        )//需要买入的总量
                    );
                } else {//小于0时，需要卖出
                    tokenSwapableAmounts[i] = -int256(//算出的结果还原成负数
                        uint256(-deltaValue).mulDiv(//mulDiv只能算uint类型
                            10 ** tokenDecimals,
                            uint256(tokenPrices[i])
                        )//需要卖出的总量
                    );
                }
            }
        }

        _swapTokens(tokens, tokenSwapableAmounts);//对每个代币进行swap

        uint256[] memory reservesAfter = new uint256[](tokens.length);//兑换完成后查出余额
        for (uint256 i = 0; i < reservesAfter.length; i++) {//遍历
            reservesAfter[i] = IERC20(tokens[i]).balanceOf(address(this));//对reservesAfter进行赋值
        }

        emit Rebalanced(reservesBefore, reservesAfter);//抛出事件，返回rebalance兑换前后
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

    function _swapTokens(//swap函数
        address[] memory tokens,//token地址
        int256[] memory tokenSwapableAmounts//每个代币的swapamount
    ) internal {
        address usdc = IETFQuoter(etfQuoter).usdc();
        // 第一步：先进行所有的卖出操作，确保有足够的USDC余额
        uint256 usdcRemaining = _sellTokens(usdc, tokens, tokenSwapableAmounts);//要卖出的换成USDC
        // 第二步：进行所有的买入操作
        usdcRemaining = _buyTokens(//用USDC买入其他代币
            usdc,
            tokens,
            tokenSwapableAmounts,
            usdcRemaining
        );
        // 如果usdc依然还有余存，按权重比例分配买入每个代币
        if (usdcRemaining > 0) {//剩余的USDC
            uint256 usdcLeft = usdcRemaining;//赋值给usdcLeft
            for (uint256 i = 0; i < tokens.length; i++) {//遍历
                uint256 amountIn = (usdcRemaining *
                    getTokenTargetWeight[tokens[i]]) / HUNDRED_PERCENT;//剩余USDC*权重/100%---要花多少USDC
                if (amountIn == 0) continue;//余额为0，继续
                if (amountIn > usdcLeft) {//由于精度问题，可能会出现大于left的情况
                    amountIn = usdcLeft;//因此将left的值赋值给amountin
                }
                (bytes memory path, ) = IETFQuoter(etfQuoter).quoteExactIn(//算出每个token的swap路径和amountin
                    usdc,
                    tokens[i],
                    amountIn
                );
                IV3SwapRouter(swapRouter).exactInput(//
                    IV3SwapRouter.ExactInputParams({
                        path: path,
                        recipient: address(this),//swap结果分配到当前地址
                        amountIn: amountIn,
                        amountOutMinimum: 1
                    })
                );
                usdcLeft -= amountIn;//usdc减去amountin
                if (usdcLeft == 0) break;//usdc没有剩余
            }
        }//usdc有余存的时候，进行这些操作
    }

    function _sellTokens(//卖出token的实现
        address usdc,//usdc地址
        address[] memory tokens,//该token的地址
        int256[] memory tokenSwapableAmounts//卖出token的数量
    ) internal returns (uint256 usdcRemaining) {返回remaining
        for (uint256 i = 0; i < tokens.length; i++) {//遍历
            if (tokenSwapableAmounts[i] < 0) {//小于0的时候才需要卖出
                uint256 amountIn = uint256(-tokenSwapableAmounts[i]);//转换成uint256正数
                (bytes memory path, ) = IETFQuoter(etfQuoter).quoteExactIn(//查询路径是多少
                    tokens[i],
                    usdc,
                    amountIn
                );
                _approveToSwapRouter(tokens[i]);//对代币进行approve，如果没approve过，则approve
                usdcRemaining += IV3SwapRouter(swapRouter).exactInput(//卖出代币，加入到remaining里面
                    IV3SwapRouter.ExactInputParams({//卖出代币
                        path: path,//路径
                        recipient: address(this),//接收地址
                        amountIn: amountIn,//amountin
                        amountOutMinimum: 1
                    })
                );
            }
        }
    }

    function _buyTokens(//实现买入代币的逻辑
        address usdc,//usdc
        address[] memory tokens,//地址
        int256[] memory tokenSwapableAmounts,//swapamount
        uint256 usdcRemaining//usdc剩余
    ) internal returns (uint256 usdcLeft) {//返回usdcLeft的值
        usdcLeft = usdcRemaining;//赋值
        _approveToSwapRouter(usdc);//approve
        for (uint256 i = 0; i < tokens.length; i++) {//遍历
            if (tokenSwapableAmounts[i] > 0) {//swapamount大于0的时候需要买入
                (bytes memory path, uint256 amountIn) = IETFQuoter(etfQuoter)
                    .quoteExactOut(//查询路径是多少，需要多少amountIn（USDC）
                        usdc,
                        tokens[i],
                        uint256(tokenSwapableAmounts[i])
                    );
                if (usdcLeft >= amountIn) {//left大于等于amountin时
                    usdcLeft -= IV3SwapRouter(swapRouter).exactOutput(//left等同于减去swap的数量？-----------amountout（买入token的数量）是确定的，
                        IV3SwapRouter.ExactOutputParams({
                            path: path,
                            recipient: address(this),
                            amountOut: uint256(tokenSwapableAmounts[i]),
                            amountInMaximum: type(uint256).max
                        })
                    );
                } else if (usdcLeft > 0) {//小于amountin，大于0时，因为余下的usdc值不够要购买的代币的数量，那么剩下的全部买入
                    (path, ) = IETFQuoter(etfQuoter).quoteExactIn(//查询买入swap的路径
                        usdc,
                        tokens[i],
                        usdcLeft
                    );
                    IV3SwapRouter(swapRouter).exactInput(//买入token
                        IV3SwapRouter.ExactInputParams({//买入
                            path: path,//路径
                            recipient: address(this),//地址
                            amountIn: usdcLeft,//剩余usdc
                            amountOutMinimum: 1
                        })
                    );
                    usdcLeft = 0;//全部卖出
                    break;//
                }
            }
        }
    }
}
