// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";
import {Exchange} from "../periphery/Exchange.sol";

contract ExchangeTest is Setup {

    Exchange internal _exchange;

    function setUp() public virtual override {
        super.setUp();
        _exchange = Exchange(address(exchange));
    }

    function test_setupOK() public {
        assertEq(_exchange.owner(), management);
    }

    function test_swapFrom(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        address _borrow = strategy.borrowToken();
        address _collateral = strategy.asset();

        if (ERC20(_borrow).decimals() < 18) _amount /= 1e12;

        airdrop(ERC20(_borrow), user, _amount);

        uint256 _balanceBeforeBorrow = ERC20(_borrow).balanceOf(user);
        uint256 _balanceBeforeCollateral = ERC20(_collateral).balanceOf(user);

        vm.startPrank(user);
        ERC20(_borrow).approve(address(exchange), _amount);
        vm.expectRevert("slippage rekt you");
        exchange.exchange(_borrow, _collateral, _amount, type(uint256).max);
        uint256 _amountOut = exchange.exchange(_borrow, _collateral, _amount, 0);
        vm.stopPrank();

        // Check user balances
        assertEq(ERC20(_borrow).balanceOf(user), _balanceBeforeBorrow - _amount);
        assertEq(ERC20(_collateral).balanceOf(user), _balanceBeforeCollateral + _amountOut);

        // Check exchange balances
        assertEq(ERC20(_borrow).balanceOf(address(exchange)), 0);
        assertEq(ERC20(_collateral).balanceOf(address(exchange)), 0);
    }

    function test_swapTo(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        address _borrow = strategy.borrowToken();
        address _collateral = strategy.asset();

        airdrop(ERC20(_collateral), user, _amount);

        uint256 _balanceBeforeBorrow = ERC20(_borrow).balanceOf(user);
        uint256 _balanceBeforeCollateral = ERC20(_collateral).balanceOf(user);

        vm.startPrank(user);
        ERC20(_collateral).approve(address(exchange), _amount);
        vm.expectRevert("slippage rekt you");
        exchange.exchange(_collateral, _borrow, _amount, type(uint256).max);
        uint256 _amountOut = exchange.exchange(_collateral, _borrow, _amount, 0);
        vm.stopPrank();

        // Check user balances
        assertEq(ERC20(_collateral).balanceOf(user), _balanceBeforeCollateral - _amount);
        assertEq(ERC20(_borrow).balanceOf(user), _balanceBeforeBorrow + _amountOut);

        // Check exchange balances
        assertEq(ERC20(_borrow).balanceOf(address(exchange)), 0);
        assertEq(ERC20(_collateral).balanceOf(address(exchange)), 0);
    }

    // ============================================================
    // Owner functions
    // ============================================================

    function test_setCurveRouter() public {
        address newRouter = address(0xBEEF);

        vm.prank(management);
        _exchange.setCurveRouter(newRouter);

        assertEq(_exchange.curveRouter(), newRouter);
    }

    function test_setCurveRouter_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_wrongCaller);
        _exchange.setCurveRouter(address(0xBEEF));
    }

    function test_setMinAmountToSell() public {
        uint256 newMin = 1e6;

        vm.prank(management);
        _exchange.setMinAmountToSell(newMin);

        assertEq(_exchange.minAmountToSell(), newMin);
    }

    function test_setMinAmountToSell_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_wrongCaller);
        _exchange.setMinAmountToSell(1e6);
    }

    function test_setCurveRoute_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        address[11] memory _route;
        uint256[5][5] memory _swapParams;
        address[5] memory _pools;

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_wrongCaller);
        _exchange.setCurveRoute(address(0), address(0), _route, _swapParams, _pools);
    }

    function test_sweep(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        ERC20 _borrow = ERC20(strategy.borrowToken());

        airdrop(_borrow, address(exchange), _amount);
        uint256 _balanceBefore = _borrow.balanceOf(management);

        vm.startPrank(management);
        exchange.sweep(_borrow);

        vm.expectRevert("!balance");
        exchange.sweep(ERC20(tokenAddrs["YFI"]));

        vm.stopPrank();

        assertEq(_borrow.balanceOf(management), _balanceBefore + _amount);
        assertEq(_borrow.balanceOf(address(exchange)), 0);
    }

    function test_sweep_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        ERC20 token = ERC20(strategy.borrowToken());

        airdrop(token, address(exchange), 1e18);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_wrongCaller);
        exchange.sweep(token);
    }

    // ============================================================
    // Ownership transfer (Ownable2Step)
    // ============================================================

    function test_transferOwnership() public {
        address newOwner = address(0xCAFE);

        vm.prank(management);
        _exchange.transferOwnership(newOwner);

        // Owner hasn't changed yet
        assertEq(_exchange.owner(), management);
        assertEq(_exchange.pendingOwner(), newOwner);

        // New owner accepts
        vm.prank(newOwner);
        _exchange.acceptOwnership();

        assertEq(_exchange.owner(), newOwner);
        assertEq(_exchange.pendingOwner(), address(0));
    }

    function test_transferOwnership_wrongCaller(
        address _wrongCaller
    ) public {
        vm.assume(_wrongCaller != management);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_wrongCaller);
        _exchange.transferOwnership(address(0xCAFE));
    }

    function test_acceptOwnership_wrongCaller(
        address _wrongCaller
    ) public {
        address newOwner = address(0xCAFE);
        vm.assume(_wrongCaller != newOwner);

        vm.prank(management);
        _exchange.transferOwnership(newOwner);

        vm.expectRevert("Ownable2Step: caller is not the new owner");
        vm.prank(_wrongCaller);
        _exchange.acceptOwnership();
    }

}
