// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {IAToken} from "@aave-v3/interfaces/IAToken.sol";
import {IPool} from "@aave-v3/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave-v3/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave-v3/interfaces/IPoolAddressesProvider.sol";
import {IVariableDebtToken} from "@aave-v3/interfaces/IVariableDebtToken.sol";
import {IPriceOracle} from "@aave-v3/interfaces/IPriceOracle.sol";

import {IExchange} from "./interfaces/IExchange.sol";
import {ICentralAprOracle} from "./interfaces/ICentralAprOracle.sol";

import {AaveOps} from "./libraries/AaveOps.sol";

import {BaseLenderBorrower, IERC4626, ERC20, SafeERC20} from "./BaseLenderBorrower.sol";

contract AaveLenderBorrowerStrategy is BaseLenderBorrower {

    using SafeERC20 for ERC20;

    // ===============================================================
    // Storage
    // ===============================================================

    /// @notice If true, `getNetBorrowApr()` will return 0,
    ///         which means we'll always consider it profitable to borrow
    bool public forceLeverage;

    /// @notice Addresses allowed to deposit
    mapping(address => bool) public allowed;

    // ===============================================================
    // Constants
    // ===============================================================

    /// @notice The RAY constant
    uint256 private constant RAY = 1e27;

    /// @notice The governance address, only one that is able to call `sweep()`
    /// @dev This is yChad
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    /// @notice The AAVE address provider
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    /// @notice The AAVE Pool contract
    IPool public immutable POOL;

    /// @notice The AAVE Pool Data Provider contract
    IPoolDataProvider public immutable POOL_DATA_PROVIDER;

    /// @notice The AAVE aToken for the asset, we get this when we supply collateral
    IAToken public immutable A_TOKEN;

    /// @notice The AAVE aToken for the borrow token, we can borrow only as much liquidity as this token has
    IAToken public immutable BORROW_A_TOKEN;

    /// @notice The AAVE variable debt token for the borrow token, we get this when we borrow
    IVariableDebtToken public immutable DEBT_TOKEN;

    /// @notice The AAVE price oracle contract
    IPriceOracle public immutable PRICE_ORACLE;

    /// @notice The exchange contract for buying/selling the borrow token
    IExchange public immutable EXCHANGE;

    /// @notice The central APR oracle contract. Used to get the lender vault's APR
    ICentralAprOracle public constant CENTRAL_APR_ORACLE =
        ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    // ===============================================================
    // Constructor
    // ===============================================================

    /// @notice Constructor
    /// @param _asset The strategy's asset
    /// @param _name The strategy's name
    /// @param _lenderVault The address of the lender vault
    /// @param _addressesProvider The address of the Aave Pool Addresses Provider
    /// @param _exchange The exchange contract for buying/selling borrow token
    /// @param _categoryId The eMode category ID to use for this strategy
    constructor(
        address _asset,
        string memory _name,
        address _lenderVault,
        address _addressesProvider,
        address _exchange,
        uint8 _categoryId
    ) BaseLenderBorrower(_asset, _name, IERC4626(_lenderVault).asset(), _lenderVault) {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressesProvider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
        POOL_DATA_PROVIDER = IPoolDataProvider(ADDRESSES_PROVIDER.getPoolDataProvider());
        PRICE_ORACLE = IPriceOracle(ADDRESSES_PROVIDER.getPriceOracle());

        (address _aToken,,) = POOL_DATA_PROVIDER.getReserveTokensAddresses(_asset);
        A_TOKEN = IAToken(_aToken);

        (address _borrowAToken,, address _debtToken) = POOL_DATA_PROVIDER.getReserveTokensAddresses(borrowToken);
        BORROW_A_TOKEN = IAToken(_borrowAToken);
        DEBT_TOKEN = IVariableDebtToken(_debtToken);

        (,,,,, bool _usageAsCollateralEnabled,,,,) = POOL_DATA_PROVIDER.getReserveConfigurationData(_asset);
        require(_usageAsCollateralEnabled, "!usageAsCollateralEnabled");
        require(!_isSupplyPaused(), "supplyPaused");
        require(!_isBorrowPaused(), "borrowPaused");

        EXCHANGE = IExchange(_exchange);
        require(EXCHANGE.BORROW() == borrowToken && EXCHANGE.COLLATERAL() == _asset, "!exchange");

        POOL.setUserEMode(_categoryId);

        ERC20(_asset).forceApprove(_exchange, type(uint256).max);
        ERC20(borrowToken).forceApprove(_exchange, type(uint256).max);

        ERC20(_asset).forceApprove(address(POOL), type(uint256).max);
        ERC20(borrowToken).forceApprove(address(POOL), type(uint256).max);
    }

    // ===============================================================
    // Management/emergency functions
    // ===============================================================

    /// @notice Set the forceLeverage flag
    /// @param _forceLeverage The new value for the forceLeverage flag
    function setForceLeverage(
        bool _forceLeverage
    ) external onlyManagement {
        forceLeverage = _forceLeverage;
    }

    /// @notice Allow (or disallow) a specific address to deposit into the strategy
    /// @param _address Address to allow or disallow
    /// @param _allowed True to allow deposits from `_address`, false to block
    function setAllowed(
        address _address,
        bool _allowed
    ) external onlyManagement {
        allowed[_address] = _allowed;
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

    // ===============================================================
    // Governance functions
    // ===============================================================

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(
        ERC20 _token
    ) external {
        require(msg.sender == GOV, "!gov");
        require(_token != asset, "!asset");
        _token.safeTransfer(GOV, _token.balanceOf(address(this)));
    }

    // ===============================================================
    // Write functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function _supplyCollateral(
        uint256 _amount
    ) internal override {
        AaveOps.supply(POOL, address(asset), _amount);
    }

    /// @inheritdoc BaseLenderBorrower
    function _withdrawCollateral(
        uint256 _amount
    ) internal override {
        AaveOps.withdraw(POOL, address(asset), _amount);
    }

    /// @inheritdoc BaseLenderBorrower
    function _borrow(
        uint256 _amount
    ) internal override {
        AaveOps.borrow(POOL, borrowToken, _amount);
    }

    /// @inheritdoc BaseLenderBorrower
    function _repay(
        uint256 _amount
    ) internal override {
        AaveOps.repay(POOL, borrowToken, _amount);
    }

    // ===============================================================
    // View functions
    // ===============================================================

    /// @inheritdoc BaseLenderBorrower
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        return allowed[_owner] || _owner == address(this) ? BaseLenderBorrower.availableDepositLimit(_owner) : 0;
    }

    /// @inheritdoc BaseLenderBorrower
    function _getPrice(
        address _asset
    ) internal view override returns (uint256) {
        return PRICE_ORACLE.getAssetPrice(_asset);
    }

    /// @inheritdoc BaseLenderBorrower
    function _isSupplyPaused() internal view override returns (bool) {
        return AaveOps.isSupplyPaused(POOL_DATA_PROVIDER, address(asset));
    }

    /// @inheritdoc BaseLenderBorrower
    function _isBorrowPaused() internal view override returns (bool) {
        return AaveOps.isBorrowPaused(POOL_DATA_PROVIDER, borrowToken);
    }

    /// @inheritdoc BaseLenderBorrower
    function _isLiquidatable() internal view override returns (bool) {
        return AaveOps.isLiquidatable(POOL);
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxCollateralDeposit() internal view override returns (uint256) {
        return AaveOps.maxCollateralDeposit(POOL_DATA_PROVIDER, A_TOKEN, address(asset));
    }

    /// @inheritdoc BaseLenderBorrower
    function _maxBorrowAmount() internal view override returns (uint256) {
        return AaveOps.maxBorrowAmount(POOL_DATA_PROVIDER, POOL, borrowToken);
    }

    /// @inheritdoc BaseLenderBorrower
    function _lenderMaxWithdraw() internal view override returns (uint256) {
        return BaseLenderBorrower._lenderMaxWithdraw() + 1; // + 1 for rounding
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetBorrowApr(
        uint256 /*_newAmount*/
    ) public view override returns (uint256) {
        return forceLeverage ? 0 : POOL.getReserveData(borrowToken).currentVariableBorrowRate / (RAY / WAD);
    }

    /// @inheritdoc BaseLenderBorrower
    function getNetRewardApr(
        uint256 _newAmount
    ) public view override returns (uint256) {
        return forceLeverage ? 1 : CENTRAL_APR_ORACLE.getStrategyApr(address(lenderVault), int256(_newAmount));
    }

    /// @inheritdoc BaseLenderBorrower
    function getLiquidateCollateralFactor() public view override returns (uint256) {
        return AaveOps.getLiquidateCollateralFactor(POOL_DATA_PROVIDER, address(asset));
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
        EXCHANGE.swap(
            _amount,
            0, // minAmount
            true // fromBorrow
        );
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
        EXCHANGE.swap(
            _amount,
            0, // minAmount
            false // fromBorrow
        );
    }

}
