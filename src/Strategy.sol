// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAToken} from "@aave-v3/interfaces/IAToken.sol";
import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave-v3/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave-v3/interfaces/IPoolAddressesProvider.sol";
import {IVariableDebtToken} from "@aave-v3/interfaces/IVariableDebtToken.sol";
import {IRewardsController} from "@aave-v3/rewards/interfaces/IRewardsController.sol";
import {IPriceOracle} from "@aave-v3/interfaces/IPriceOracle.sol";

import {IVaultAPROracle} from "./interfaces/IVaultAPROracle.sol";

import {BaseLenderBorrower, IERC4626, ERC20, Math, SafeERC20} from "./BaseLenderBorrower.sol";
import "forge-std/console2.sol";

contract AaveLenderBorrowerStrategy is BaseLenderBorrower {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Constants
    // ===============================================================

    uint256 private constant RAY = 1e27;
    uint256 private constant INTEREST_RATE_MODE = 2; // interestRateMode 2 for Variable, 1 is deprecated on v3.2.0
    uint16 private constant REFERRAL = 0;

    /// @notice The governance address, only one that is able to call `sweep()`
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool public immutable POOL;
    IPoolDataProvider private immutable PROTOCOL_DATA_PROVIDER;
    IRewardsController private immutable REWARDS_CONTROLLER;
    IAToken public immutable A_TOKEN;
    IAToken public immutable BORROW_A_TOKEN;
    IVariableDebtToken public immutable DEBT_TOKEN;
    IPriceOracle public immutable PRICE_ORACLE;

    /// @notice The lender vault APR oracle contract
    IVaultAPROracle public constant VAULT_APR_ORACLE = IVaultAPROracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @notice Constructor
    /// @param _asset The strategy's asset
    /// @param _name The strategy's name
    /// @param _lenderVault The address of the lender vault
    /// @param _addressesProvider The address of the Aave Pool Addresses Provider
    /// @param _categoryId The eMode category ID to use for this strategy
    constructor(
        address _asset,
        string memory _name,
        address _lenderVault,
        address _addressesProvider,
        uint8 _categoryId
    ) BaseLenderBorrower(_asset, _name, IERC4626(_lenderVault).asset(), _lenderVault) {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressesProvider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
        PROTOCOL_DATA_PROVIDER = IPoolDataProvider(ADDRESSES_PROVIDER.getPoolDataProvider());
        REWARDS_CONTROLLER = IRewardsController(ADDRESSES_PROVIDER.getAddress(keccak256("INCENTIVES_CONTROLLER")));
        PRICE_ORACLE = IPriceOracle(ADDRESSES_PROVIDER.getPriceOracle());

        (address _aToken,,) = PROTOCOL_DATA_PROVIDER.getReserveTokensAddresses(_asset);
        A_TOKEN = IAToken(_aToken);

        (address _borrowAToken,, address _debtToken) = PROTOCOL_DATA_PROVIDER.getReserveTokensAddresses(borrowToken);
        BORROW_A_TOKEN = IAToken(_borrowAToken);
        DEBT_TOKEN = IVariableDebtToken(_debtToken);

        (,,,,, bool _usageAsCollateralEnabled,,,,) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(_asset);
        require(_usageAsCollateralEnabled, "!usageAsCollateralEnabled");
        require(!_isSupplyPaused(), "supplyPaused");
        require(!_isBorrowPaused(), "borrowPaused");

        // Set eMode
        POOL.setUserEMode(_categoryId); // @todo -- test this

        ERC20(_asset).forceApprove(address(POOL), type(uint256).max);
        ERC20(borrowToken).forceApprove(address(POOL), type(uint256).max);
    }

    // ===============================================================
    // Management functions
    // ===============================================================

    // ===============================================================
    // Write functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _supplyCollateral(
        uint256 _amount
    ) internal override {
        if (_amount > 0) POOL.supply(address(asset), _amount, address(this), REFERRAL);
    }

    /// @inheritdoc BaseLenderBorrower
    function _withdrawCollateral(
        uint256 _amount
    ) internal override {
        if (_amount > 0) POOL.withdraw(address(asset), _amount, address(this));
    }

    /// @inheritdoc BaseLenderBorrower
    function _borrow(
        uint256 _amount
    ) internal override {
        if (_amount > 0) POOL.borrow(borrowToken, _amount, INTEREST_RATE_MODE, REFERRAL, address(this));
    }

    /// @inheritdoc BaseLenderBorrower
    function _repay(
        uint256 _amount
    ) internal override {
        if (_amount > 0) POOL.repay(borrowToken, _amount, INTEREST_RATE_MODE, address(this));
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _getPrice(
        address _asset
    ) internal view override returns (uint256) {
        return PRICE_ORACLE.getAssetPrice(_asset);
    }

    /// @inheritdoc BaseLenderBorrower
    function _isSupplyPaused() internal view override returns (bool) {
        (,,,,,,,, bool _isActive, bool _isFrozen) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(address(asset));
        return !_isActive || _isFrozen || PROTOCOL_DATA_PROVIDER.getPaused(address(asset));
    }

    /// @inheritdoc BaseLenderBorrower
    function _isBorrowPaused() internal view override returns (bool) {
        (,,,,,, bool _borrowingEnabled,, bool _isActive, bool _isFrozen) =
            PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(borrowToken);
        return !_borrowingEnabled || !_isActive || _isFrozen || PROTOCOL_DATA_PROVIDER.getPaused(borrowToken);
    }

    /// @inheritdoc BaseLenderBorrower
    function _isLiquidatable() internal view override returns (bool) {
        (,,,,, uint256 _healthFactor) = POOL.getUserAccountData(address(this));
        return _healthFactor < WAD; // @todo
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxCollateralDeposit() internal view override returns (uint256) {
        (, uint256 _supplyCap) = PROTOCOL_DATA_PROVIDER.getReserveCaps(address(asset));
        if (_supplyCap == 0) return type(uint256).max;

        uint256 _scaledSupplyCap = _supplyCap * 10 ** asset.decimals();
        uint256 _currentSupply = A_TOKEN.totalSupply() + asset.balanceOf(address(this));
        if (_scaledSupplyCap <= _currentSupply) return 0;

        return _scaledSupplyCap - _currentSupply;
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxBorrowAmount() internal view override returns (uint256) {
        (uint256 _borrowCap,) = PROTOCOL_DATA_PROVIDER.getReserveCaps(borrowToken);
        return Math.min(
            _borrowCap == 0 ? type(uint256).max : _borrowCap * 10 ** ERC20(borrowToken).decimals(),
            ERC20(borrowToken).balanceOf(address(BORROW_A_TOKEN)) // Available liquidity
        );
    }

    /// @inheritdoc BaseLenderBorrower
    function _lenderMaxWithdraw() internal view override returns (uint256) {
        return BaseLenderBorrower._lenderMaxWithdraw() + 1; // + 1 for rounding
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetBorrowApr(
        uint256 /*_newAmount*/
    ) public view override returns (uint256) {
        return POOL.getReserveData(borrowToken).currentVariableBorrowRate / (RAY / WAD);
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetRewardApr(
        uint256 _newAmount
    ) public view override returns (uint256) {
        return VAULT_APR_ORACLE.getStrategyApr(address(lenderVault), int256(_newAmount));
    }

    /// @inheritdoc BaseLenderBorrower
    function getLiquidateCollateralFactor() public view override returns (uint256) {
        (, uint256 _ltv,,,,,,,,) = PROTOCOL_DATA_PROVIDER.getReserveConfigurationData(address(asset));
        return _ltv * (WAD / MAX_BPS);
    }

    /// @inheritdoc BaseLenderBorrower
    function balanceOfCollateral() public view override returns (uint256) {
        return A_TOKEN.balanceOf(address(this));
    }

    /// @inheritdoc BaseLenderBorrower
    function balanceOfDebt() public view override returns (uint256) {
        return ERC20(address(DEBT_TOKEN)).balanceOf(address(this));
    }

    // ===============================================================
    // Harvest / Token conversions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _claimRewards() internal pure override {
        return;
    }

    /// @inheritdoc BaseLenderBorrower
    function _claimAndSellRewards() internal override {
        uint256 _loose = balanceOfBorrowToken();
        uint256 _have = balanceOfLentAssets() + _loose;
        uint256 _owe = balanceOfDebt();
        if (_owe >= _have) return;

        uint256 _toSell = _have - _owe;
        if (_toSell > _loose) _withdrawBorrowToken(_toSell - _loose);

        _loose = balanceOfBorrowToken();

        _sellBorrowToken(_toSell > _loose ? _loose : _toSell);
    }

    /// @inheritdoc BaseLenderBorrower
    function _sellBorrowToken(
        uint256 _amount
    ) internal virtual override {
        // AMM.exchange(CRVUSD_INDEX, ASSET_INDEX, _amount, 0);
        // @todo
    }

    /// @inheritdoc BaseLenderBorrower
    function _buyBorrowToken() internal virtual override {
        uint256 _borrowTokenStillOwed = borrowTokenOwedBalance();
        uint256 _maxAssetBalance = _fromUsd(_toUsd(_borrowTokenStillOwed, borrowToken), address(asset));
        _buyBorrowToken(_maxAssetBalance);
    }

    /// @notice Buy borrow token
    /// @param _amount The amount of asset to sale
    function _buyBorrowToken(
        uint256 _amount
    ) internal {
        // AMM.exchange(ASSET_INDEX, CRVUSD_INDEX, _amount, 0);
        // @todo
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(
        ERC20 _token
    ) external {
        require(msg.sender == GOV, "!gov");
        require(_token != asset, "!asset");
        _token.safeTransfer(GOV, _token.balanceOf(address(this)));
    }

    /// @notice Manually buy borrow token
    /// @dev Potentially can never reach `_buyBorrowToken()` in `_liquidatePosition()`
    ///      because of lender vault accounting (i.e. `balanceOfLentAssets() == 0` is never true)
    function buyBorrowToken(
        uint256 _amount
    ) external onlyEmergencyAuthorized {
        if (_amount == type(uint256).max) _amount = balanceOfAsset();
        _buyBorrowToken(_amount);
    }

}
