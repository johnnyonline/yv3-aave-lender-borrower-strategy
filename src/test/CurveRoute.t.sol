// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {Exchange} from "../periphery/Exchange.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CurveRouteTest is Test {

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    address constant TRICRYPTO_USDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B; // USDC=0, WBTC=1, WETH=2
    address constant cbBTC_WBTC = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802; // cbBTC=0, WBTC=1

    address management = address(1);
    address user = address(10);

    Exchange exchange;

    function setUp() public {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 24_570_258));

        exchange = new Exchange(management);

        // USDC -> cbBTC (2 hops: USDC -> WBTC via tricrypto, WBTC -> cbBTC via cbBTC/WBTC)
        address[11] memory _fromRoute;
        _fromRoute[0] = USDC;
        _fromRoute[1] = TRICRYPTO_USDC;
        _fromRoute[2] = WBTC;
        _fromRoute[3] = cbBTC_WBTC;
        _fromRoute[4] = cbBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(0), 1, 1, 3, 3]; // USDC(0) -> WBTC(1), swap_type=1, pool_type=3 (tricrypto), n_coins=3
        _fromParams[1] = [uint256(1), 0, 1, 1, 2]; // WBTC(1) -> cbBTC(0), swap_type=1, pool_type=1 (stableswap), n_coins=2

        // cbBTC -> USDC (2 hops: cbBTC -> WBTC via cbBTC/WBTC, WBTC -> USDC via tricrypto)
        address[11] memory _toRoute;
        _toRoute[0] = cbBTC;
        _toRoute[1] = cbBTC_WBTC;
        _toRoute[2] = WBTC;
        _toRoute[3] = TRICRYPTO_USDC;
        _toRoute[4] = USDC;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 1, 2]; // cbBTC(0) -> WBTC(1), swap_type=1, pool_type=1 (stableswap), n_coins=2
        _toParams[1] = [uint256(1), 0, 1, 3, 3]; // WBTC(1) -> USDC(0), swap_type=1, pool_type=3 (tricrypto), n_coins=3

        address[5] memory _pools;

        vm.startPrank(management);
        exchange.setCurveRoute(USDC, cbBTC, _fromRoute, _fromParams, _pools);
        exchange.setCurveRoute(cbBTC, USDC, _toRoute, _toParams, _pools);
        vm.stopPrank();
    }

    function test_swapFromBorrow() public {
        uint256 _amount = 10_000e6; // 10k USDC
        deal(USDC, user, _amount);

        vm.startPrank(user);
        ERC20(USDC).approve(address(exchange), _amount);
        uint256 _out = exchange.exchange(USDC, cbBTC, _amount, 0);
        vm.stopPrank();

        console2.log("USDC in:", _amount);
        console2.log("cbBTC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(exchange)), 0);
        assertEq(ERC20(cbBTC).balanceOf(address(exchange)), 0);
    }

    function test_swapToCollateral() public {
        uint256 _amount = 0.1e8; // 0.1 cbBTC
        deal(cbBTC, user, _amount);

        vm.startPrank(user);
        ERC20(cbBTC).approve(address(exchange), _amount);
        uint256 _out = exchange.exchange(cbBTC, USDC, _amount, 0);
        vm.stopPrank();

        console2.log("cbBTC in:", _amount);
        console2.log("USDC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(exchange)), 0);
        assertEq(ERC20(cbBTC).balanceOf(address(exchange)), 0);
    }

}
