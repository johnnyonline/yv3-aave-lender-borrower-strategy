// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {Exchange} from "../periphery/Exchange.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Deploy} from "../../script/Deploy.s.sol";

contract CurveRouteTest is Test, Deploy {

    address user = address(10);

    function setUp() public {
        vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), 24_780_930));
    }

    // ============================================================
    // cbBTC/USDC (2 hops: tricryptoUSDC, cbBTC/wBTC)
    // ============================================================

    function test_usdcToCbbtc() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdcCbbtcRoute(address(_exchange));

        uint256 _amount = 10_000e6;
        deal(USDC, user, _amount);

        vm.startPrank(user);
        ERC20(USDC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(USDC, CBBTC, _amount, 0);
        vm.stopPrank();

        console2.log("USDC in:", _amount);
        console2.log("cbBTC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    function test_cbbtcToUsdc() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdcCbbtcRoute(address(_exchange));

        uint256 _amount = 0.1e8;
        deal(CBBTC, user, _amount);

        vm.startPrank(user);
        ERC20(CBBTC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(CBBTC, USDC, _amount, 0);
        vm.stopPrank();

        console2.log("cbBTC in:", _amount);
        console2.log("USDC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    // ============================================================
    // cbBTC/PYUSD (3 hops: PayPool, tricryptoUSDC, cbBTC/wBTC)
    // ============================================================

    function test_pyusdToCbbtc() public {
        Exchange _exchange = new Exchange(address(this));
        _setPyusdCbbtcRoute(address(_exchange));

        uint256 _amount = 10_000e6;
        deal(PYUSD, user, _amount);

        vm.startPrank(user);
        ERC20(PYUSD).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(PYUSD, CBBTC, _amount, 0);
        vm.stopPrank();

        console2.log("PYUSD in:", _amount);
        console2.log("cbBTC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(PYUSD).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    function test_cbbtcToPyusd() public {
        Exchange _exchange = new Exchange(address(this));
        _setPyusdCbbtcRoute(address(_exchange));

        uint256 _amount = 0.1e8;
        deal(CBBTC, user, _amount);

        vm.startPrank(user);
        ERC20(CBBTC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(CBBTC, PYUSD, _amount, 0);
        vm.stopPrank();

        console2.log("cbBTC in:", _amount);
        console2.log("PYUSD out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(PYUSD).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    // ============================================================
    // cbBTC/RLUSD (3 hops: RLUSD/USDC, tricryptoUSDC, cbBTC/wBTC)
    // ============================================================

    function test_rlusdToCbbtc() public {
        Exchange _exchange = new Exchange(address(this));
        _setRlusdCbbtcRoute(address(_exchange));

        uint256 _amount = 10_000e18;
        deal(RLUSD, user, _amount);

        vm.startPrank(user);
        ERC20(RLUSD).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(RLUSD, CBBTC, _amount, 0);
        vm.stopPrank();

        console2.log("RLUSD in:", _amount);
        console2.log("cbBTC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(RLUSD).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    function test_cbbtcToRlusd() public {
        Exchange _exchange = new Exchange(address(this));
        _setRlusdCbbtcRoute(address(_exchange));

        uint256 _amount = 0.1e8;
        deal(CBBTC, user, _amount);

        vm.startPrank(user);
        ERC20(CBBTC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(CBBTC, RLUSD, _amount, 0);
        vm.stopPrank();

        console2.log("cbBTC in:", _amount);
        console2.log("RLUSD out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(RLUSD).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    // ============================================================
    // cbBTC/USDT (2 hops: tricrypto2, cbBTC/wBTC)
    // ============================================================

    function test_usdtToCbbtc() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdtCbbtcRoute(address(_exchange));

        uint256 _amount = 10_000e6;
        deal(USDT, user, _amount);

        vm.startPrank(user);
        SafeERC20.forceApprove(IERC20(USDT), address(_exchange), _amount);
        uint256 _out = _exchange.exchange(USDT, CBBTC, _amount, 0);
        vm.stopPrank();

        console2.log("USDT in:", _amount);
        console2.log("cbBTC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDT).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    function test_cbbtcToUsdt() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdtCbbtcRoute(address(_exchange));

        uint256 _amount = 0.1e8;
        deal(CBBTC, user, _amount);

        vm.startPrank(user);
        ERC20(CBBTC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(CBBTC, USDT, _amount, 0);
        vm.stopPrank();

        console2.log("cbBTC in:", _amount);
        console2.log("USDT out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDT).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(CBBTC).balanceOf(address(_exchange)), 0);
    }

    // ============================================================
    // wstETH/USDC (2 hops: crvUSD/USDC, tricryptollama)
    // ============================================================

    function test_usdcToWsteth() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdcWstethRoute(address(_exchange));

        uint256 _amount = 10_000e6;
        deal(USDC, user, _amount);

        vm.startPrank(user);
        ERC20(USDC).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(USDC, WSTETH, _amount, 0);
        vm.stopPrank();

        console2.log("USDC in:", _amount);
        console2.log("wstETH out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(WSTETH).balanceOf(address(_exchange)), 0);
    }

    function test_wstethToUsdc() public {
        Exchange _exchange = new Exchange(address(this));
        _setUsdcWstethRoute(address(_exchange));

        uint256 _amount = 1e18;
        deal(WSTETH, user, _amount);

        vm.startPrank(user);
        ERC20(WSTETH).approve(address(_exchange), _amount);
        uint256 _out = _exchange.exchange(WSTETH, USDC, _amount, 0);
        vm.stopPrank();

        console2.log("wstETH in:", _amount);
        console2.log("USDC out:", _out);
        assertGt(_out, 0);
        assertEq(ERC20(USDC).balanceOf(address(_exchange)), 0);
        assertEq(ERC20(WSTETH).balanceOf(address(_exchange)), 0);
    }

}
