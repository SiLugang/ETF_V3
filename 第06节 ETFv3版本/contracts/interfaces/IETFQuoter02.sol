// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IETFQuoter} from "./IETFQuoter.sol";

interface IETFQuoter02 is IETFQuoter {
    function getTokenTargetValues(
        address etf
    )
        external
        view
        returns (
            uint24[] memory tokenTargetWeights,
            uint256[] memory tokenTargetValues,
            uint256[] memory tokenReserves
        );
}
