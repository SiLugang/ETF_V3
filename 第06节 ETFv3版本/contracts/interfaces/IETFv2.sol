// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IETFv1} from "./IETFv1.sol";

interface IETFv2 is IETFv1 {
    error InvalidSwapPath(bytes swapPath);
    error InvalidArrayLength();
    error OverSlippage();
    error SafeTransferETHFailed();

    event InvestedWithETH(address to, uint256 mintAmount, uint256 paidAmount);
    event InvestedWithToken(
        address indexed srcToken,
        address to,
        uint256 mintAmount,
        uint256 totalPaid
    );
    event RedeemedToETH(address to, uint256 burnAmount, uint256 receivedAmount);
    event RedeemedToToken(
        address indexed dstToken,
        address to,
        uint256 burnAmount,
        uint256 receivedAmount
    );

    function investWithETH(
        address to,
        uint256 mintAmount,
        bytes[] memory swapPaths
    ) external payable;

    function investWithToken(
        address srcToken,
        address to,
        uint256 mintAmount,
        uint256 maxSrcTokenAmount,
        bytes[] memory swapPaths
    ) external;

    function redeemToETH(
        address to,
        uint256 burnAmount,
        uint256 minETHAmount,
        bytes[] memory swapPaths
    ) external;

    function redeemToToken(
        address dstToken,
        address to,
        uint256 burnAmount,
        uint256 minDstTokenAmount,
        bytes[] memory swapPaths
    ) external;

    function swapRouter() external view returns (address);

    function weth() external view returns (address);
}
