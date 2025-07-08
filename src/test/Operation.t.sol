// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IBaseStrategy} from "@tokenized-strategy/interfaces/IBaseStrategy.sol";

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract OperationTest is Setup {

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

    // function test_dontLeaveDebtBehind_realizesLoss( // @todo
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

    //     checkStrategyTotals(strategy, _amount, _amount, 0);
    //     assertEq(strategy.totalAssets(), _amount, "!totalAssets");
    //     assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
    //     assertApproxEqAbs(strategy.balanceOfCollateral(), _amount, 1, "!balanceOfCollateral");
    //     assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

    //     // Earn Interest
    //     skip(1 days);

    //     // override availableWithdrawLimit
    //     vm.mockCall(
    //         address(strategy),
    //         abi.encodeWithSelector(IBaseStrategy.availableWithdrawLimit.selector),
    //         abi.encode(type(uint256).max)
    //     );

    //     // lose some lent
    //     vm.startPrank(address(strategy));
    //     ERC20(lenderVault).transfer(address(420), ERC20(lenderVault).balanceOf(address(strategy)) * 10 / 100);
    //     vm.stopPrank();

    //     vm.startPrank(emergencyAdmin);
    //     strategy.manualWithdraw(address(0), strategy.balanceOfCollateral() * 10 / 100);
    //     strategy.buyBorrowToken(type(uint256).max); // sell all loose collateral
    //     vm.stopPrank();

    //     assertGe(strategy.balanceOfLentAssets() + strategy.balanceOfBorrowToken(), strategy.balanceOfDebt(), "!lent");

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Redeem all funds. Default maxLoss == 10_000.
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     // We should not have got the full amount out.
    //     assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

    //     // make sure there's no debt
    //     assertEq(strategy.balanceOfDebt(), 0, "!debt");
    //     assertEq(strategy.balanceOfCollateral(), 0, "!collateral");
    // }

    // function test_operation_overWarningLTV_depositLeversDown(
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     checkStrategyTotals(strategy, _amount, _amount, 0);
    //     assertEq(strategy.totalAssets(), _amount, "!totalAssets");
    //     assertRelApproxEq(strategy.getCurrentLTV(), targetLTV, 1000);
    //     assertApproxEq(strategy.balanceOfCollateral(), _amount, 3, "!balanceOfCollateral");
    //     assertRelApproxEq(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1000);

    //     // Withdrawl some collateral to pump LTV
    //     uint256 collToSell = strategy.balanceOfCollateral() * 20 / 100;
    //     vm.prank(emergencyAdmin);
    //     strategy.manualWithdraw(address(0), collToSell);

    //     uint256 warningLTV = (strategy.getLiquidateCollateralFactor() * strategy.warningLTVMultiplier()) / MAX_BPS;

    //     assertGt(strategy.getCurrentLTV(), warningLTV);
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     assertRelApproxEq(strategy.getCurrentLTV(), targetLTV, 1000);
    // }

    // function test_operation_lostLentAssets(
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Set protocol fee to 0 and perf fee to 0
    //     setFees(0, 0);

    //     // Strategist makes initial deposit and opens a trove
    //     uint256 strategistDeposit = strategistDepositAndOpenTrove(true);

    //     assertEq(strategy.totalAssets(), strategistDeposit, "!strategistTotalAssets");

    //     uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     checkStrategyTotals(strategy, _amount + strategistDeposit, _amount + strategistDeposit, 0);
    //     assertEq(strategy.totalAssets(), _amount + strategistDeposit, "!totalAssets");
    //     assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
    //     assertApproxEqAbs(strategy.balanceOfCollateral(), _amount + strategistDeposit, 3, "!balanceOfCollateral");
    //     assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

    //     uint256 vaultLoss = strategy.balanceOfLentAssets() * 5 / 100; // 5% loss
    //     vm.prank(address(strategy));
    //     ERC20(address(lenderVault)).transfer(address(6969), vaultLoss);

    //     // Set health check to accept loss
    //     vm.prank(management);
    //     strategy.setLossLimitRatio(5_000); // 50% loss

    //     // Report loss
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();

    //     // Check return Values
    //     assertEq(profit, 0, "!profit");
    //     assertGe(loss, 0, "!loss");

    //     // Shutdown the strategy (can't repay entire debt without)
    //     vm.startPrank(emergencyAdmin);
    //     strategy.shutdownStrategy();

    //     vm.expectRevert(NotEnoughBoldBalance.selector); // Not enough BOLD to repay the loan
    //     strategy.emergencyWithdraw(type(uint256).max);

    //     // Withdraw enough collateral to repay the loan
    //     uint256 collToSell = strategy.balanceOfCollateral() * 25 / 100;
    //     strategy.manualWithdraw(address(0), collToSell);

    //     // Sell collateral to buy debt
    //     strategy.buyBorrowToken(type(uint256).max);

    //     // Close trove and repay the loan
    //     strategy.emergencyWithdraw(type(uint256).max);

    //     // Sell any leftover borrow token to asset
    //     strategy.sellBorrowToken(type(uint256).max);

    //     vm.stopPrank();

    //     uint256 balanceBefore = asset.balanceOf(user);

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     assertLt(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

    //     // Around 5% loss
    //     assertApproxEqRel(asset.balanceOf(user), balanceBefore + _amount, 5e16); // 5%

    //     balanceBefore = asset.balanceOf(strategist);

    //     // Report
    //     vm.prank(keeper);
    //     strategy.report();

    //     vm.startPrank(strategist);
    //     strategy.redeem(strategy.maxRedeem(strategist), strategist, strategist);
    //     vm.stopPrank();

    //     assertLt(asset.balanceOf(strategist), balanceBefore + strategistDeposit, "!final balance");

    //     // Around 5% loss
    //     assertApproxEqRel(asset.balanceOf(strategist), balanceBefore + strategistDeposit, 6e16); // 6% :O

    //     checkStrategyTotals(strategy, 0, 0, 0);
    // }

    // function test_operation_liquidation(
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Strategist makes initial deposit and opens a trove
    //     uint256 strategistDeposit = strategistDepositAndOpenTrove(true);

    //     assertEq(strategy.totalAssets(), strategistDeposit, "!strategistTotalAssets");

    //     uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     checkStrategyTotals(strategy, _amount + strategistDeposit, _amount + strategistDeposit, 0);
    //     assertEq(strategy.totalAssets(), _amount + strategistDeposit, "!totalAssets");
    //     assertApproxEqRel(strategy.getCurrentLTV(), targetLTV, 1e15); // 0.1%
    //     assertApproxEqAbs(strategy.balanceOfCollateral(), _amount + strategistDeposit, 3, "!balanceOfCollateral");
    //     assertApproxEqRel(strategy.balanceOfDebt(), strategy.balanceOfLentAssets(), 1e15); // 0.1%

    //     // Simulate a liquidation
    //     simulateLiquidation();

    //     // Check position
    //     assertEq(strategy.balanceOfDebt(), 0, "!debt");
    //     assertEq(strategy.balanceOfCollateral(), 0, "!collateral");

    //     // Sell all borrow token
    //     (bool trigger,) = strategy.tendTrigger();
    //     assertTrue(trigger, "sellRewards");

    //     // Sell the rewards
    //     vm.prank(keeper);
    //     strategy.tend();

    //     // We sold the borrow token
    //     (trigger,) = strategy.tendTrigger();
    //     assertFalse(trigger, "!sellRewards");

    //     // Set health check to accept loss
    //     vm.prank(management);
    //     strategy.setLossLimitRatio(5_000); // 50% loss

    //     // Report loss
    //     vm.prank(keeper);
    //     (uint256 profit, uint256 loss) = strategy.report();

    //     // Check return Values
    //     assertEq(profit, 0, "!profit");
    //     assertGt(loss, 0, "!loss");

    //     // Shutdown the strategy
    //     vm.startPrank(emergencyAdmin);
    //     strategy.shutdownStrategy();
    //     strategy.emergencyWithdraw(type(uint256).max);
    //     vm.stopPrank();

    //     // Withdraw all funds
    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     // Strategist withdraws all funds
    //     vm.prank(strategist);
    //     strategy.redeem(strategistDeposit, strategist, strategist, 0);

    //     checkStrategyTotals(strategy, 0, 0, 0);
    // }

    // function test_tendTrigger(
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * strategy.targetLTVMultiplier()) / MAX_BPS;

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     (bool trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // Skip some time
    //     skip(1 days);

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // Borrow too much.
    //     uint256 toBorrow = (
    //         strategy.balanceOfCollateral()
    //             * ((strategy.getLiquidateCollateralFactor() * (strategy.warningLTVMultiplier() + 100)) / MAX_BPS)
    //     ) / 1e18;

    //     toBorrow = _fromUsd(_toUsd(toBorrow, address(asset)), borrowToken);

    //     vm.startPrank(address(strategy));
    //     IController(strategy.CONTROLLER()).borrow_more(0, toBorrow - strategy.balanceOfDebt());
    //     vm.stopPrank();

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(trigger, "warning ltv");

    //     // Even with a 0 for max Tend Base Fee its true
    //     vm.startPrank(management);
    //     strategy.setMaxGasPriceToTend(0);
    //     vm.stopPrank();

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(trigger, "warning ltv 2");

    //     // Even with a 0 for max Tend Base Fee its true
    //     vm.startPrank(management);
    //     strategy.setMaxGasPriceToTend(200e9);
    //     vm.stopPrank();

    //     vm.prank(keeper);
    //     strategy.tend();

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger, "post tend");

    //     vm.prank(keeper);
    //     strategy.report();

    //     // Lower LTV
    //     uint256 borrowed = strategy.balanceOfDebt();
    //     airdrop(ERC20(borrowToken), address(strategy), borrowed / 2);

    //     vm.prank(management);
    //     strategy.manualRepayDebt();

    //     assertLt(strategy.getCurrentLTV(), targetLTV);

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(trigger);

    //     vm.prank(keeper);
    //     strategy.tend();

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger, "post tend");

    //     vm.prank(user);
    //     strategy.redeem(_amount, user, user);

    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger);
    // }

    // function test_tendTrigger_noRewards(
    //     uint256 _amount
    // ) public {
    //     vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

    //     // Deposit into strategy
    //     mintAndDepositIntoStrategy(strategy, user, _amount);

    //     (bool trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     // (almost) zero out rewards
    //     vm.mockCall(
    //         address(strategy.VAULT_APR_ORACLE()),
    //         abi.encodeWithSelector(IVaultAPROracle.getExpectedApr.selector),
    //         abi.encode(1)
    //     );
    //     assertEq(strategy.getNetRewardApr(0), 1);

    //     // Now that it's unprofitable to borrow, we should tend
    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(trigger);

    //     vm.prank(management);
    //     strategy.setForceLeverage(true);

    //     assertTrue(strategy.forceLeverage());
    //     assertEq(strategy.getNetBorrowApr(0), 0);

    //     // Now that we force leverage, we should not tend
    //     (trigger,) = strategy.tendTrigger();
    //     assertTrue(!trigger);

    //     vm.expectRevert("!management");
    //     strategy.setForceLeverage(false);
    // }

}
