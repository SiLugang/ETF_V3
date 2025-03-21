// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IETFQuoter02} from "./interfaces/IETFQuoter02.sol";
import {ETFQuoter} from "./ETFQuoter.sol";
import {IETFv3} from "./interfaces/IETFv3.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

contract ETFQuoter02 is IETFQuoter02, ETFQuoter {
    constructor(
        address uniswapV3Quoter_,
        address weth_,
        address usdc_
    ) ETFQuoter(uniswapV3Quoter_, weth_, usdc_) {}

    function getTokenTargetValues(//返回三个数组
        address etf//该etf
    )
        external
        view
        returns (
            uint24[] memory tokenTargetWeights,//代币目标权重
            uint256[] memory tokenTargetValues,//代币目标市值
            uint256[] memory tokenReserves//代币剩余
        )
    {
        IETFv3 etfContract = IETFv3(etf);

        address[] memory tokens;//代币地址数组
        int256[] memory tokenPrices;//代币价格数组
        uint256[] memory tokenMarketValues;//代币市值数组
        uint256 totalValues;
        (tokens, tokenPrices, tokenMarketValues, totalValues) = etfContract
            .getTokenMarketValues();

        tokenTargetWeights = new uint24[](tokens.length);
        tokenTargetValues = new uint256[](tokens.length);
        tokenReserves = new uint256[](tokens.length);//三个数组初始化

        for (uint256 i = 0; i < tokens.length; i++) {//遍历
            tokenTargetWeights[i] = etfContract.getTokenTargetWeight(tokens[i]);//该代币权重直接读取可得
            tokenTargetValues[i] =
                (totalValues * tokenTargetWeights[i]) /
                1000000;//该代币目标市值等于总市值*该代币目标权重
            tokenReserves[i] = IERC20(tokens[i]).balanceOf(etf);//该代币余额等于读取
        }
    }
}
