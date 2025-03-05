// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IETFQuoter} from "./interfaces/IETFQuoter.sol";
import {IETFv1} from "./interfaces/IETFv1.sol";
import {IUniswapV3Quoter} from "./interfaces/IUniswapV3Quoter.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";

contract ETFQuoter is IETFQuoter {
    using FullMath for uint256;

    uint24[4] public fees;
    address public immutable weth;
    address public immutable usdc;

    IUniswapV3Quoter public immutable uniswapV3Quoter;

    constructor(address uniswapV3Quoter_, address weth_, address usdc_) {
        uniswapV3Quoter = IUniswapV3Quoter(uniswapV3Quoter_);
        weth = weth_;
        usdc = usdc_;
        fees = [100, 500, 3000, 10000];
    }

    function quoteInvestWithToken(
        address etf,
        address srcToken,
        uint256 mintAmount
    )
        external
        view
        override
        returns (uint256 srcAmount, bytes[] memory swapPaths)
    {
        address[] memory tokens = IETFv1(etf).getTokens();
        uint256[] memory tokenAmounts = IETFv1(etf).getInvestTokenAmounts(
            mintAmount
        );

        swapPaths = new bytes[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (srcToken == tokens[i]) {
                srcAmount += tokenAmounts[i];
                swapPaths[i] = bytes.concat(
                    bytes20(srcToken),
                    bytes3(fees[0]),
                    bytes20(srcToken)
                );
            } else {
                (bytes memory path, uint256 amountIn) = quoteExactOut(
                    srcToken,
                    tokens[i],
                    tokenAmounts[i]
                );
                srcAmount += amountIn;
                swapPaths[i] = path;
            }
        }
    }

    function quoteRedeemToToken(
        address etf,
        address dstToken,
        uint256 burnAmount
    )
        external
        view
        override
        returns (uint256 dstAmount, bytes[] memory swapPaths)
    {
        address[] memory tokens = IETFv1(etf).getTokens();
        uint256[] memory tokenAmounts = IETFv1(etf).getRedeemTokenAmounts(
            burnAmount
        );

        swapPaths = new bytes[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (dstToken == tokens[i]) {
                dstAmount += tokenAmounts[i];
                swapPaths[i] = bytes.concat(
                    bytes20(dstToken),
                    bytes3(fees[0]),
                    bytes20(dstToken)
                );
            } else {
                (bytes memory path, uint256 amountOut) = quoteExactIn(
                    tokens[i],
                    dstToken,
                    tokenAmounts[i]
                );
                dstAmount += amountOut;
                swapPaths[i] = path;
            }
        }
    }

    function quoteExactOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) public view returns (bytes memory path, uint256 amountIn) {
        bytes[] memory allPaths = getAllPaths(tokenOut, tokenIn);
        for (uint256 i = 0; i < allPaths.length; i++) {
            try
                uniswapV3Quoter.quoteExactOutput(allPaths[i], amountOut)
            returns (
                uint256 amountIn_,
                uint160[] memory,
                uint32[] memory,
                uint256
            ) {
                if (amountIn_ > 0 && (amountIn == 0 || amountIn_ < amountIn)) {
                    amountIn = amountIn_;
                    path = allPaths[i];
                }
            } catch {}
        }
    }

    function quoteExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (bytes memory path, uint256 amountOut) {
        bytes[] memory allPaths = getAllPaths(tokenIn, tokenOut);
        for (uint256 i = 0; i < allPaths.length; i++) {
            try uniswapV3Quoter.quoteExactInput(allPaths[i], amountIn) returns (
                uint256 amountOut_,
                uint160[] memory,
                uint32[] memory,
                uint256
            ) {
                if (amountOut_ > amountOut) {
                    amountOut = amountOut_;
                    path = allPaths[i];
                }
            } catch {}
        }
    }

    function getAllPaths(
        address tokenA,
        address tokenB
    ) public view returns (bytes[] memory paths) {
        // 计算路径数量
        uint totalPaths = fees.length + (fees.length * fees.length * 2);
        paths = new bytes[](totalPaths);

        uint256 index = 0;

        // 1. 生成直接路径：tokenA -> fee -> tokenB
        for (uint256 i = 0; i < fees.length; i++) {
            paths[index] = bytes.concat(
                bytes20(tokenA),
                bytes3(fees[i]),
                bytes20(tokenB)
            );
            index++;
        }

        // 2. 生成中间代币路径：tokenA -> fee1 -> intermediary -> fee2 -> tokenB
        address[2] memory intermediaries = [weth, usdc];
        for (uint256 i = 0; i < intermediaries.length; i++) {
            for (uint256 j = 0; j < fees.length; j++) {
                for (uint256 k = 0; k < fees.length; k++) {
                    paths[index] = bytes.concat(
                        bytes20(tokenA),
                        bytes3(fees[j]),
                        bytes20(intermediaries[i]),
                        bytes3(fees[k]),
                        bytes20(tokenB)
                    );
                    index++;
                }
            }
        }
    }
}
