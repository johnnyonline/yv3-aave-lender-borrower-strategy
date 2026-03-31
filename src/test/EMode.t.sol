// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {Exchange} from "../periphery/Exchange.sol";
import {AaveLenderBorrowerStrategy as Strategy, ERC20, IPool} from "../Strategy.sol";
import {StrategyFactory} from "../StrategyFactory.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract EModeTest is Test {

    address constant LBTC = 0x8236a87084f8B84306f72007F36F2618A5634494;
    address constant ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant LENDER_VAULT = 0x5cee43aa4Beb43E114C50d2127b206a6b95F1151; // Curve WBTC LB

    uint8 constant EMODE_CATEGORY = 4; // BTC-correlated (LBTC reserve ID 37)

    address user = address(10);
    address management = address(1);

    IStrategyInterface strategy;

    function setUp() public {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 24_570_258));

        StrategyFactory factory = new StrategyFactory(management, address(3), address(4), address(5));

        address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address CURVE_POOL = 0x2f3bC4c27A4437AeCA13dE0e37cdf1028f3706F0;

        Exchange exchange = new Exchange(management);

        // WBTC -> LBTC
        address[11] memory _fromRoute;
        _fromRoute[0] = WBTC;
        _fromRoute[1] = CURVE_POOL;
        _fromRoute[2] = LBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(1), 0, 1, 2, 2]; // i=1 (WBTC), j=0 (LBTC), swap_type=1, pool_type=2 (crypto), n_coins=2

        // LBTC -> WBTC
        address[11] memory _toRoute;
        _toRoute[0] = LBTC;
        _toRoute[1] = CURVE_POOL;
        _toRoute[2] = WBTC;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 2, 2]; // i=0 (LBTC), j=1 (WBTC)

        address[5] memory _pools;

        vm.startPrank(management);
        exchange.setCurveRoute(WBTC, LBTC, _fromRoute, _fromParams, _pools);
        exchange.setCurveRoute(LBTC, WBTC, _toRoute, _toParams, _pools);
        vm.stopPrank();

        strategy = IStrategyInterface(
            factory.newStrategy(
                LBTC, "LBTC/WBTC eMode", LENDER_VAULT, ADDRESSES_PROVIDER, address(exchange), EMODE_CATEGORY
            )
        );
    }

    function test_eMode() public {
        // Verify eMode LTV is higher than non-eMode
        uint256 liqFactor = strategy.getLiquidateCollateralFactor();
        console2.log("eMode LTV:", liqFactor);
        assertGt(liqFactor, 0.7e18, "eMode LTV should be high");
    }

}
