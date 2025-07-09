// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ILenderBorrower} from "./ILenderBorrower.sol";

interface IStrategyInterface is ILenderBorrower {

    function POOL() external view returns (address);
    function PRICE_ORACLE() external view returns (address);
    function VAULT_APR_ORACLE() external view returns (address);
    function forceLeverage() external view returns (bool);

    function setForceLeverage(
        bool _forceLeverage
    ) external;

    function sweep(
        address _token
    ) external;
    function buyBorrowToken(
        uint256 _amount
    ) external;

}
