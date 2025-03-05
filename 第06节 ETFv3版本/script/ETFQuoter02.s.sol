// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ETFQuoter02} from "../src/etf/ETFQuoter02.sol";

contract ETFQuoter02Script is Script {
    address uniswapV3Quoter;
    address weth9;
    address usdc;

    function setUp() public {
        uniswapV3Quoter = 0x419D1c2331faAFDbdf9144C64a3E07f19D217ebD;
        weth9 = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        usdc = 0x22e18Fc2C061f2A500B193E5dBABA175be7cdD7f;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ETFQuoter02 etfQuoter = new ETFQuoter02(uniswapV3Quoter, weth9, usdc);
        console.log("ETFQuoter:", address(etfQuoter));

        vm.stopBroadcast();
    }
}
