// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.25 ^0.8.20 ^0.8.25;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// src/interfaces/ICurveStableSwap.sol

interface ICurveStableSwap is IERC20, IERC20Metadata {
    /**
     * @dev Get token address by index
     */
    function coins(uint256 i) external returns (address);

    /**
     * @dev Add liquidity to a Curve 2pool
     */
    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

    /**
     * @dev Add liquidity to a Curve 3pool
     */
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

    /**
     * @dev Get amount of received token X in swap for Y (send Y, receive X)
     */
    function get_dx(int128 i, int128 j, uint256 exchangeAmount) external returns (uint256);

    /**
     * @dev Get amount of received token Y in swap for X (send X, receive Y)
     */
    function get_dy(int128 i, int128 j, uint256 exchangeAmount) external returns (uint256);

    /**
     * @dev Exchange i for j
     */
    function exchange(int128 i, int128 j, uint256 exchangeAmount, uint256 minReceiveAmount)
        external
        returns (uint256);

    /**
     * @dev Exchange i for j with receiver
     */
    function exchange(int128 i, int128 j, uint256 exchangeAmount, uint256 minReceiveAmount, address receiver)
        external
        returns (uint256);
}

interface ICurveStableSwapV2 is IERC20, IERC20Metadata {
    /**
     * @dev Get token address by index
     */
    function coins(uint256 i) external view returns (address);

    /**
     * @dev Get price of token to LP
     */
    function price_oracle() external view returns (uint256);

    /**
     * @dev Add liquidity to a Curve 2pool
     */
    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

    /**
     * @dev Add liquidity to a Curve 3pool
     */
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

    /**
     * @dev Get amount of received token X in swap for Y (send Y, receive X)
     */
    function get_dx(int128 i, int128 j, uint256 exchangeAmount) external view returns (uint256);

    /**
     * @dev Get amount of received token Y in swap for X (send X, receive Y)
     */
    function get_dy(int128 i, int128 j, uint256 exchangeAmount) external view returns (uint256);

    /**
     * @dev Exchange i for j
     */
    function exchange(uint256 i, uint256 j, uint256 exchangeAmount, uint256 minReceiveAmount)
        external
        returns (uint256);

    /**
     * @dev Exchange i for j with receiver
     */
    function exchange(uint256 i, uint256 j, uint256 exchangeAmount, uint256 minReceiveAmount, address receiver)
        external
        returns (uint256);
}

// src/Dough.sol

interface IDough {
    error TriggerOverflow();
    error RegistryFull();

    event RefillBalance(address _safe, uint256 _breadExchanged, uint256 _eureRecieved);
    event SafeRegistered(address _safe, uint256 _refillTrigger, uint256 _refillAmount);

    struct SafeSettings {
        uint256 refillTrigger;
        uint256 refillAmount;
    }

    function SLIPPAGE() external view returns (uint256);

    function counter() external view returns (uint256);

    function safeSettings(address _safe) external view returns (uint256 _s1, uint256 _s2);

    function register(uint256 _refillTrigger, uint256 _refillAmount) external;

    function resolveBalances() external view returns (bool, bytes memory _payload);

    function swapBreadToEure(bytes calldata _payload) external;
}

contract Dough is IDough {
    // TODO: check slippage math
    uint256 public constant SLIPPAGE = 0.99 ether; // 1% slippage
    uint256 constant WAD = 1 ether;

    // tokens
    IERC20 constant GNOSIS_BREAD = IERC20(0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3);
    IERC20 constant GNOSIS_WXDAI = IERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);
    IERC20 constant GNOSIS_3CRV_USD = IERC20(0x1337BedC9D22ecbe766dF105c9623922A27963EC);
    IERC20 constant GNOSIS_EURE = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);

    // Curve liquidity pools
    ICurveStableSwap constant CRV_WXDAI_BREAD = ICurveStableSwap(0xf3D8F3dE71657D342db60dd714c8a2aE37Eac6B4);
    ICurveStableSwap constant CRV_WXDAI_USDC_USDT = ICurveStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    ICurveStableSwapV2 constant CRV_EURE_USD = ICurveStableSwapV2(0x056C6C5e684CeC248635eD86033378Cc444459B0);

    uint256 public counter; // set limit for address(this) to limit array-based DOS (out of gas) attack
    uint256 internal _maxRegistry;

    address[] internal _safeRegistry;
    mapping(address safe => SafeSettings) _safeSettings;

    constructor(uint256 _maxR) {
        _maxRegistry = _maxR;

        GNOSIS_BREAD.approve(address(CRV_WXDAI_BREAD), type(uint256).max);
        GNOSIS_WXDAI.approve(address(CRV_WXDAI_USDC_USDT), type(uint256).max);
        GNOSIS_3CRV_USD.approve(address(CRV_EURE_USD), type(uint256).max);
    }

    function register(uint256 _refillTrigger, uint256 _refillAmount) external {
        // TODO: confirm Safe is associated with Gnosis Pay

        if (_refillTrigger >= _refillAmount) revert TriggerOverflow();
        if (counter >= _maxRegistry) revert RegistryFull();

        _safeSettings[msg.sender] = SafeSettings(_refillTrigger, _refillAmount);
        _safeRegistry.push(msg.sender);
        counter++;

        emit SafeRegistered(msg.sender, _refillTrigger, _refillAmount);
    }

    function resolveBalances() external view returns (bool, bytes memory _payload) {
        // enforce caller is from PowerPool

        uint256 _l = _getArrayLength();

        if (_l > 0) {
            uint256 _price = CRV_EURE_USD.price_oracle();
            address[] memory _safes = new address[](_l);
            uint256[] memory _amounts = new uint256[](_l);

            uint256 _index;
            for (uint256 i; i < counter; i++) {
                address _safe = _safeRegistry[i];
                SafeSettings memory ss = _safeSettings[_safe];

                uint256 _eureBal = GNOSIS_EURE.balanceOf(_safe);
                if (_eureBal < ss.refillTrigger) {
                    uint256 _amount = (ss.refillAmount - _eureBal) * WAD * 102 / 100 / _price;

                    if (GNOSIS_BREAD.balanceOf(_safe) > _amount) {
                        _safes[_index] = _safe;
                        _amounts[_index] = _amount;
                        _index++;
                    }
                }
            }
            _payload = abi.encodeWithSelector(IDough.swapBreadToEure.selector, abi.encode(_safes, _amounts));
            return (true, _payload);
        } else {
            return (false, _payload);
        }
    }

    function swapBreadToEure(bytes calldata _payload) external {
        /**
         * TODO: enforce caller is from PowerPool (for security)
         *      - call agent contract
         *      - compare msg.sender to the list of keepers in the agent contract
         */
        (address[] memory _safes, uint256[] memory _amounts) = abi.decode(_payload, (address[], uint256[]));

        uint256 _l = _safes.length;
        for (uint256 i; i < _l; i++) {
            address _safe = _safes[i];
            uint256 _amount = _amounts[i];

            GNOSIS_BREAD.transferFrom(_safe, address(this), _amount);
            uint256 _wxdai = CRV_WXDAI_BREAD.exchange(0, 1, _amount, _amount * SLIPPAGE / WAD);
            uint256 _3usd = CRV_WXDAI_USDC_USDT.add_liquidity([_wxdai, 0, 0], _wxdai * SLIPPAGE / WAD);

            uint256 minSwapReturn = _3usd * CRV_EURE_USD.price_oracle() * SLIPPAGE / WAD ** 2;
            uint256 _eure = CRV_EURE_USD.exchange(1, 0, _3usd, minSwapReturn, _safe);

            emit RefillBalance(_safe, _amount, _eure);
        }
    }

    function safeSettings(address _safe) public view returns (uint256 _s1, uint256 _s2) {
        SafeSettings memory ss = _safeSettings[_safe];
        _s1 = ss.refillTrigger;
        _s2 = ss.refillAmount;
    }

    function _getArrayLength() internal view returns (uint256 _l) {
        for (uint256 i; i < counter; i++) {
            address _safe = _safeRegistry[i];
            (uint256 _s1,) = safeSettings(_safe);
            if (GNOSIS_EURE.balanceOf(_safe) < _s1) {
                _l++;
            }
        }
    }
}
