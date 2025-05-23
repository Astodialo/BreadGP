// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IERC20} from '@oz/token/ERC20/IERC20.sol';
import {ICurveStableSwap, ICurveStableSwapV2} from 'src/interfaces/ICurveStableSwap.sol';

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
