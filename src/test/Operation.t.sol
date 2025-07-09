// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IBaseStrategy} from "@tokenized-strategy/interfaces/IBaseStrategy.sol";

import "forge-std/console2.sol";
import {Setup, ERC20, IPool, IStrategyInterface, IVaultAPROracle} from "./utils/Setup.sol";

contract OperationTest is Setup {

    uint256 private constant INTEREST_RATE_MODE = 2;
    uint16 private constant REFERRAL = 0;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(management);
        strategy.setProfitMaxUnlockTime(0);
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    // function test_invalidDeployment() public {
    //     // strategyFactory.newStrategy(
    //     //             address(asset),
    //     //             "Tokenized Strategy",
    //     //             address(lenderVault),
    //     //             address(addressesProvider),
    //     //             address(exchange),
    //     //             uint8(0)
    //     //         )
    //     vm.expectRevert("!exchange");
    //     strategyFactory.newStrategy(
    //         IAddressesRegistry(wrongAddressesRegistry),
    //         IStrategy(address(lenderVault)),
    //         AggregatorInterface(address(0)),
    //         IExchange(address(exchange)),
    //         "Tokenized Strategy"
    //     );

    //     vm.expectRevert();
    //     strategyFactory.newStrategy(
    //         IAddressesRegistry(addressesRegistry),
    //         IStrategy(tokenAddrs["YFI"]),
    //         AggregatorInterface(address(0)),
    //         IExchange(address(exchange)),
    //         "Tokenized Strategy"
    //     );

    //     vm.expectRevert("!priceFeed");
    //     strategyFactory.newStrategy(
    //         IAddressesRegistry(addressesRegistry),
    //         IStrategy(address(lenderVault)),
    //         AggregatorInterface(address(tokenAddrs["YFI"])),
    //         IExchange(address(exchange)),
    //         "Tokenized Strategy"
    //     );

    //     vm.expectRevert();
    //     strategyFactory.newStrategy(
    //         IAddressesRegistry(addressesRegistry),
    //         IStrategy(address(lenderVault)),
    //         AggregatorInterface(address(0)),
    //         IExchange(address(0)),
    //         "Tokenized Strategy"
    //     );
    // }

    function test_operation(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Set protocol fee to 0 and perf fee to 0
        setFees(0, 0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_profitableReport_withFees() public {
        uint256 _amount = maxFuzzAmount / 100;

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_manualRepayDebt(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Earn Interest
        skip(1 days);

        // lower LTV
        uint256 borrowed = strategy.balanceOfDebt();
        airdrop(ERC20(strategy.borrowToken()), address(strategy), borrowed / 4);

        vm.expectRevert("!emergency authorized");
        strategy.manualRepayDebt();

        vm.prank(management);
        strategy.manualRepayDebt();

        assertLt(strategy.getCurrentLTV(), targetLTV);

        // Report profit
        vm.prank(keeper);
        strategy.report();

        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore, "!final balance");
    }

    function test_partialWithdraw_lowerLTV(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Earn Interest
        skip(1 days);

        // lower LTV
        uint256 borrowed = strategy.balanceOfDebt();
        airdrop(ERC20(strategy.borrowToken()), address(strategy), borrowed / 4);

        vm.prank(management);
        strategy.manualRepayDebt();

        assertLt(strategy.getCurrentLTV(), targetLTV);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount / 2, user, user, 1);

        assertGe(asset.balanceOf(user), ((balanceBefore + (_amount / 2)) * 9_999) / MAX_BPS, "!final balance");
    }

    function test_leaveDebtBehind_realizesLoss(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        vm.startPrank(management);
        strategy.setLeaveDebtBehind(true);
        vm.stopPrank();

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Pay without earning
        skip(30 days);

        // override availableWithdrawLimit
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.availableWithdrawLimit.selector),
            abi.encode(type(uint256).max)
        );

        uint256 balanceBefore = asset.balanceOf(user);

        // Redeem all funds. Default maxLoss == 10_000.
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // We should not have got the full amount out.
        assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // make sure there's still debt
        assertGt(strategy.balanceOfDebt(), 0, "!debt");
        assertGt(strategy.balanceOfCollateral(), 0, "!collateral");
    }

    function test_dontLeaveDebtBehind_realizesLoss(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Earn Interest
        skip(1 days);

        // override availableWithdrawLimit
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IBaseStrategy.availableWithdrawLimit.selector),
            abi.encode(type(uint256).max)
        );

        // lose some lent
        vm.startPrank(address(strategy));
        ERC20(strategy.lenderVault()).transfer(
            address(420), ERC20(strategy.lenderVault()).balanceOf(address(strategy)) * 10 / 100
        );
        vm.stopPrank();

        vm.startPrank(emergencyAdmin);
        strategy.manualWithdraw(address(0), strategy.balanceOfCollateral() * 10 / 100);
        strategy.buyBorrowToken(type(uint256).max); // sell all loose collateral
        vm.stopPrank();

        assertGe(strategy.balanceOfLentAssets() + strategy.balanceOfBorrowToken(), strategy.balanceOfDebt(), "!lent");

        uint256 balanceBefore = asset.balanceOf(user);

        // Redeem all funds. Default maxLoss == 10_000.
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // We should not have got the full amount out.
        assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // make sure there's no debt
        assertEq(strategy.balanceOfDebt(), 0, "!debt");
        assertEq(strategy.balanceOfCollateral(), 0, "!collateral");
    }

    function test_operation_overWarningLTV_depositLeversDown(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Withdrawl some collateral to pump LTV
        uint256 collToSell = strategy.balanceOfCollateral() * 20 / 100;
        vm.prank(emergencyAdmin);
        strategy.manualWithdraw(address(0), collToSell);

        uint256 warningLTV = (strategy.getLiquidateCollateralFactor() * strategy.warningLTVMultiplier()) / MAX_BPS;

        assertGt(strategy.getCurrentLTV(), warningLTV);
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
    }

    function test_operation_lostLentAssets() public {
        uint256 _amount = maxFuzzAmount / 100;

        // Set protocol fee to 0 and perf fee to 0
        setFees(0, 0);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        uint256 vaultLoss = strategy.balanceOfLentAssets() * 5 / 100; // 5% loss
        vm.startPrank(address(strategy));
        ERC20(strategy.lenderVault()).transfer(address(6969), vaultLoss);
        vm.stopPrank();

        // Set health check to accept loss
        vm.prank(management);
        strategy.setLossLimitRatio(5_000); // 50% loss

        // Report loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertEq(profit, 0, "!profit");
        assertGe(loss, 0, "!loss");

        vm.startPrank(emergencyAdmin);

        // Withdraw enough collateral to repay the loan
        uint256 collToSell = strategy.balanceOfCollateral() * 25 / 100;
        strategy.manualWithdraw(address(0), collToSell);

        // Sell collateral to buy debt
        strategy.buyBorrowToken(type(uint256).max);

        // Repay the debt
        strategy.manualRepayDebt();

        vm.stopPrank();

        // Report
        vm.prank(keeper);
        strategy.report();

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.startPrank(user);
        strategy.redeem(strategy.maxRedeem(user), user, user);
        vm.stopPrank();

        assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Around 5% loss
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, 5e16); // 5%

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_operation_liquidation() public {
        uint256 _amount = maxFuzzAmount / 100;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
        assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

        // Simulate a liquidation
        simulateLiquidation();

        // Check position
        assertEq(strategy.balanceOfDebt(), 0, "!debt");
        assertApproxEqAbs(strategy.balanceOfCollateral(), 0, 1, "!collateral");

        // Rekt
        (bool trigger,) = strategy.tendTrigger();
        assertFalse(trigger, "sellRewards");

        // Set health check to accept loss
        vm.prank(management);
        strategy.setLossLimitRatio(5_000); // 50% loss

        // Sell lent assets we still have and report loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertEq(profit, 0, "!profit");
        assertGt(loss, 0, "!loss");

        uint256 dust = 10_000;

        // We should be back in business
        assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
        assertGt(strategy.balanceOfCollateral(), dust);
        assertGt(strategy.balanceOfDebt(), dust);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.startPrank(user);
        strategy.redeem(strategy.maxRedeem(user), user, user);
        vm.stopPrank();

        assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Around 50% loss
        assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, 50e16); // 50%

        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_tendTrigger() public {
        uint256 _amount = maxFuzzAmount / 100;

        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Borrow too much.
        uint256 toBorrow = (
            strategy.balanceOfCollateral()
                * ((strategy.getLiquidateCollateralFactor() * (strategy.warningLTVMultiplier() + 100)) / MAX_BPS)
        ) / 1e18;

        toBorrow = _fromUsd(_toUsd(toBorrow, strategy.asset()), strategy.borrowToken());

        vm.startPrank(address(strategy));
        IPool(strategy.POOL()).borrow(
            strategy.borrowToken(), toBorrow - strategy.balanceOfDebt(), INTEREST_RATE_MODE, REFERRAL, address(strategy)
        );
        vm.stopPrank();

        (trigger,) = strategy.tendTrigger();
        assertTrue(trigger, "warning ltv");

        // Even with a 0 for max Tend Base Fee its true
        vm.startPrank(management);
        strategy.setMaxGasPriceToTend(0);
        vm.stopPrank();

        (trigger,) = strategy.tendTrigger();
        assertTrue(trigger, "warning ltv 2");

        // Even with a 0 for max Tend Base Fee its true
        vm.startPrank(management);
        strategy.setMaxGasPriceToTend(200e9);
        vm.stopPrank();

        vm.prank(keeper);
        strategy.tend();

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger, "post tend");

        vm.prank(keeper);
        strategy.report();

        // Lower LTV
        uint256 borrowed = strategy.balanceOfDebt();
        airdrop(ERC20(strategy.borrowToken()), address(strategy), borrowed / 2);

        vm.prank(management);
        strategy.manualRepayDebt();

        assertLt(strategy.getCurrentLTV(), targetLTV);

        (trigger,) = strategy.tendTrigger();
        assertTrue(trigger);

        vm.prank(keeper);
        strategy.tend();

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger, "post tend");

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    function test_tendTrigger_noRewards(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        // (almost) zero out rewards
        vm.mockCall(
            strategy.VAULT_APR_ORACLE(), abi.encodeWithSelector(IVaultAPROracle.getStrategyApr.selector), abi.encode(1)
        );
        assertEq(strategy.getNetRewardApr(0), 1);

        // Now that it's unprofitable to borrow, we should tend
        (trigger,) = strategy.tendTrigger();
        assertTrue(trigger);

        vm.prank(management);
        strategy.setForceLeverage(true);

        assertTrue(strategy.forceLeverage());
        assertEq(strategy.getNetBorrowApr(0), 0);

        // Now that we force leverage, we should not tend
        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.expectRevert("!management");
        strategy.setForceLeverage(false);
    }

}
