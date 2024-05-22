// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";
import {IComposableStablePool} from "src/interfaces/IComposableStablePool.sol";

import {IAsset} from "@balancer-v2/interfaces/contracts/vault/IAsset.sol";
import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

/// @title RoboSaver: turn your Gnosis Pay card into an automated savings account!
/// @author onchainification.xyz
/// @notice Deposit and withdraw $EURe from your Gnosis Pay card to a liquidity pool
contract RoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                     DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enum representing the different types of pool actions
    /// @custom:value0 WITHDRAW Withdraw $EURe from the pool to the card
    /// @custom:value1 DEPOSIT Deposit $EURe from the card into the pool
    enum PoolAction {
        WITHDRAW,
        DEPOSIT
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint16 constant MAX_BPS = 10_000;

    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public immutable CARD;

    IERC20 constant STEUR = IERC20(0x004626A008B1aCdC4c74ab51644093b155e59A23);
    IERC20 constant EURE = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);

    IVault public constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IComposableStablePool constant BPT_STEUR_EURE = IComposableStablePool(0x06135A9Ae830476d3a941baE9010B63732a055F4);

    bytes32 public immutable BPT_STEUR_EURE_POOL_ID;
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    IDelayModifier public delayModule;
    IRolesModifier public rolesModule;

    address public keeper;
    uint256 public buffer;
    uint16 public slippage;

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a withdrawal pool transaction is being queued up
    /// @param safe The address of the card
    /// @param amount The amount of $EURe to withdraw from the pool
    /// @param timestamp The timestamp of the transaction
    event PoolWithdrawalQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a deposit pool transaction is being queued up
    /// @param safe The address of the card
    /// @param amount The amount of $EURe to deposit into the pool
    /// @param timestamp The timestamp of the transaction
    event PoolDepositQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when an adjustment pool transaction is being queued up
    /// @dev Event is leveraged by off-chain service to execute the queued transaction
    /// @param target The address of the target contract
    /// @param payload The payload of the transaction to be executed on the target contract
    event AdjustPoolTxDataQueued(address indexed target, bytes payload);

    /// @notice Emitted when the admin sets a new keeper address
    /// @param admin The address of the admin
    /// @param oldKeeper The address of the old keeper
    /// @param newKeeper The address of the new keeper
    event SetKeeper(address indexed admin, address oldKeeper, address newKeeper);

    /// @notice Emitted when the admin sets a new buffer value
    /// @param admin The address of the admin
    /// @param oldBuffer The value of the old buffer
    /// @param newBuffer The value of the new buffer
    event SetBuffer(address indexed admin, uint256 oldBuffer, uint256 newBuffer);

    /// @notice Emitted when the admin sets a new slippage value
    /// @param admin The address of the admin
    /// @param oldSlippage The value of the old slippage
    /// @param newSlippage The value of the new slippage
    event SetSlippage(address indexed admin, uint256 oldSlippage, uint256 newSlippage);

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NotKeeper(address agent);
    error NotAdmin(address agent);

    error ZeroAddressValue();
    error ZeroUintValue();

    error TooHighBps();

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enforce that the function is called by the keeper only
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper(msg.sender);
        _;
    }

    /// @notice Enforce that the function is called by the admin only
    modifier onlyAdmin() {
        if (msg.sender != CARD) revert NotAdmin(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address _delayModule, address _rolesModule, address _keeper, uint256 _buffer, uint16 _slippage) {
        delayModule = IDelayModifier(_delayModule);
        rolesModule = IRolesModifier(_rolesModule);
        keeper = _keeper;
        buffer = _buffer;
        slippage = _slippage;

        CARD = delayModule.avatar();
        BPT_STEUR_EURE_POOL_ID = BPT_STEUR_EURE.getPoolId();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Assigns a new keeper address
    /// @param _keeper The address of the new keeper
    function setKeeper(address _keeper) external onlyAdmin {
        if (_keeper == address(0)) revert ZeroAddressValue();

        address oldKeeper = keeper;
        keeper = _keeper;

        emit SetKeeper(msg.sender, oldKeeper, keeper);
    }

    /// @notice Assigns a new value for the buffer responsible for deciding when there is a surplus
    /// @param _buffer The value of the new buffer
    function setBuffer(uint256 _buffer) external onlyAdmin {
        if (_buffer == 0) revert ZeroUintValue();

        uint256 oldBuffer = buffer;
        buffer = _buffer;

        emit SetBuffer(msg.sender, oldBuffer, buffer);
    }

    /// @notice Adjust the maximum slippage the user is comfortable with
    /// @param _slippage The value of the new slippage in bps (so 10_000 is 100%)
    function setSlippage(uint16 _slippage) external onlyAdmin {
        if (_slippage >= MAX_BPS) revert TooHighBps();

        uint16 oldSlippage = slippage;
        slippage = _slippage;

        emit SetSlippage(msg.sender, oldSlippage, slippage);
    }

    /// @notice Check if there is a surplus or deficit of $EURe on the card
    /// @return adjustPoolNeeded True if there is a deficit or surplus; false otherwise
    /// @return execPayload The payload of the needed transaction
    function checker() external view returns (bool adjustPoolNeeded, bytes memory execPayload) {
        uint256 balance = EURE.balanceOf(CARD);
        (, uint128 dailyAllowance,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        if (balance < dailyAllowance) {
            /// @notice there is a deficit; we need to withdraw from the pool
            uint256 deficit = dailyAllowance - balance;
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.WITHDRAW, deficit));
        } else if (balance > dailyAllowance + buffer) {
            /// @notice there is a surplus; we need to deposit into the pool
            uint256 surplus = balance - (dailyAllowance + buffer);
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.DEPOSIT, surplus));
        }

        /// @notice neither deficit nor surplus; no action needed
        return (false, bytes("Neither deficit nor surplus; no action needed"));
    }

    /// @notice Adjust the pool by depositing or withdrawing $EURe
    /// @param _action The action to take: deposit or withdraw
    /// @param _amount The amount of $EURe to deposit or withdraw
    function adjustPool(PoolAction _action, uint256 _amount) external onlyKeeper {
        if (_action == PoolAction.WITHDRAW) {
            /// @dev Close the pool in case the $EURe available for withdrawal is less than the deficit
            uint256 withdrawableEure =
                BPT_STEUR_EURE.balanceOf(CARD) * BPT_STEUR_EURE.getRate() * (MAX_BPS - slippage) / MAX_BPS;
            if (withdrawableEure < _amount) {
                _poolClose(CARD, withdrawableEure);
            } else {
                _poolWithdrawal(CARD, _amount);
            }
        } else if (_action == PoolAction.DEPOSIT) {
            _poolDeposit(CARD, _amount);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   INTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Close the pool position by withdrawing all to $EURe
    /// @param _card The address of the card to withdraw to
    /// @return request_ The exit pool request as per Balancer's interface
    function _poolClose(address _card, uint256 _minAmountOut)
        internal
        returns (IVault.ExitPoolRequest memory request_)
    {
        /// @dev All asset related arrays should always follow this (alphabetical) order
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        /// @dev Allow for one wei of slippage
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[2] = _minAmountOut - 1;

        /// @dev The `exitTokenIndex` for $EURe is 2
        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, BPT_STEUR_EURE.balanceOf(_card), 2);
        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        bytes memory exitPoolPayload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, _card, payable(_card), request_);

        /// @dev Queue the transaction into the delay module
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, exitPoolPayload, 0);

        emit AdjustPoolTxDataQueued(address(BALANCER_VAULT), abi.encode(request_));
        emit PoolWithdrawalQueued(_card, _minAmountOut, block.timestamp);
    }

    /// @notice Withdraw $EURe from the pool
    /// @param _card The address of the card to withdraw to
    /// @param _deficit The amount of $EURe to withdraw from the pool
    /// @return request_ The exit pool request as per Balancer's interface
    function _poolWithdrawal(address _card, uint256 _deficit)
        internal
        returns (IVault.ExitPoolRequest memory request_)
    {
        /// @dev All asset related arrays should always follow this (alphabetical) order
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        /// @dev Allow for one wei of slippage
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[2] = _deficit - 1;

        /// @dev For some reason the `amountsOut` array does NOT include the bpt token itself
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _deficit;

        /// @dev Naive calculation of the `maxBPTAmountIn` based on the bpt rate and slippage %
        uint256 maxBPTAmountIn = minAmountsOut[2] * MAX_BPS * 1e18 / (MAX_BPS - slippage) / BPT_STEUR_EURE.getRate();

        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn);
        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        bytes memory exitPoolPayload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, _card, payable(_card), request_);

        /// @dev Queue the transaction into the delay module
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, exitPoolPayload, 0);

        emit AdjustPoolTxDataQueued(address(BALANCER_VAULT), abi.encode(request_));
        emit PoolWithdrawalQueued(_card, _deficit, block.timestamp);
    }

    /// @notice Deposit $EURe into the pool
    /// @param _card The address of the card to deposit from
    /// @param _surplus The amount of $EURe to deposit into the pool
    /// @return calls_ The calls needed approve $EURe and join the pool
    function _poolDeposit(address _card, uint256 _surplus) internal returns (IMulticall.Call[] memory) {
        /// @dev Approve our $EURe to the Balancer Vault
        bytes memory approvalPayload =
            abi.encodeWithSignature("approve(address,uint256)", address(BALANCER_VAULT), _surplus);

        /// @dev Prepare the join pool request
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[2] = _surplus;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _surplus;

        /// @dev Naive calculation of the `minimumBPT` to receive based on the bpt rate and slippage %
        uint256 minimumBPT = _surplus * (MAX_BPS - slippage) * 1e18 / MAX_BPS / BPT_STEUR_EURE.getRate();

        bytes memory userData =
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);
        bytes memory joinPoolPayload =
            abi.encodeWithSelector(IVault.joinPool.selector, BPT_STEUR_EURE_POOL_ID, _card, _card, request);

        /// @dev Batch approval and pool join into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(EURE), approvalPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), joinPoolPayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        /// @dev Queue the transaction into the delay module
        /// @dev Last argument `1` stands for `OperationType.DelegateCall`
        delayModule.execTransactionFromModule(MULTICALL3, 0, multicallPayload, 1);

        emit AdjustPoolTxDataQueued(MULTICALL3, abi.encode(calls_));
        emit PoolDepositQueued(_card, _surplus, block.timestamp);

        return calls_;
    }
}
