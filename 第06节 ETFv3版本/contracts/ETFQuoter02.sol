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

    function getTokenTargetValues(
        address etf
    )
        external
        view
        returns (
            uint24[] memory tokenTargetWeights,
            uint256[] memory tokenTargetValues,
            uint256[] memory tokenReserves
        )
    {
        IETFv3 etfContract = IETFv3(etf);

        address[] memory tokens;
        int256[] memory tokenPrices;
        uint256[] memory tokenMarketValues;
        uint256 totalValues;
        (tokens, tokenPrices, tokenMarketValues, totalValues) = etfContract
            .getTokenMarketValues();

        tokenTargetWeights = new uint24[](tokens.length);
        tokenTargetValues = new uint256[](tokens.length);
        tokenReserves = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokenTargetWeights[i] = etfContract.getTokenTargetWeight(tokens[i]);
            tokenTargetValues[i] =
                (totalValues * tokenTargetWeights[i]) /
                1000000;
            tokenReserves[i] = IERC20(tokens[i]).balanceOf(etf);
        }
    }
}
