// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {BeefyAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IBeefyVault, IBeefyBooster, IBeefyBalanceCheck} from "../../../../vault/adapter/beefy/BeefyAdapter.sol";
import {BeefyTestConfigStorage, BeefyTestConfig} from "./BeefyTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract BeefyAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IBeefyBooster beefyBooster;
    IBeefyVault beefyVault;
    IBeefyBalanceCheck beefyBalanceCheck;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("POLYGON_RPC_URL"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new BeefyTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        createAdapter();

        (address _beefyVault, address _beefyBooster, ) = abi.decode(
            testConfig,
            (address, address, uint256)
        );
        beefyVault = IBeefyVault(_beefyVault);
        beefyBooster = IBeefyBooster(_beefyBooster);
        beefyBalanceCheck = IBeefyBalanceCheck(
            _beefyBooster == address(0) ? _beefyVault : _beefyBooster
        );

        setUpBaseTest(
            IERC20(IBeefyVault(beefyVault).want()),
            adapter,
            address(0),
            10,
            "Beefy ",
            true
        );

        vm.label(_beefyVault, "beefyVault");
        vm.label(_beefyBooster, "beefyBooster");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function createAdapter() public override {
        adapter = IAdapter(address(new BeefyAdapter()));
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(beefyVault),
            asset.balanceOf(address(beefyVault)) + amount
        );
        beefyVault.earn();
    }

    function iouBalance() public view override returns (uint256) {
        return beefyBalanceCheck.balanceOf(address(adapter));
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
        assertEq(
            adapter.totalAssets(),
            iouBalance().mulDiv(
                beefyVault.balance(),
                beefyVault.totalSupply(),
                Math.Rounding.Down
            ),
            string.concat("totalAssets != beefy assets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), beefyVault.want(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "Popcorn Beefy",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("popB-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(beefyVault)),
            type(uint256).max,
            "allowance"
        );

        // Test Beefy Config Boundaries
        createAdapter();
        (
            address _beefyVault,
            address _beefyBooster,
            uint256 _beefyWithdrawalFee
        ) = abi.decode(
                testConfigStorage.getTestConfig(0),
                (address, address, uint256)
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                BeefyAdapter.InvalidBeefyWithdrawalFee.selector,
                51
            )
        );
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(0),
            abi.encode(_beefyVault, _beefyBooster, uint256(51))
        );

        // Using Retired USD+-MATIC vLP vault on polygon
        vm.expectRevert(
            abi.encodeWithSelector(
                BeefyAdapter.InvalidBeefyVault.selector,
                address(0x3af3563Ba5C68EB7DCbAdd2dF0FcE4CC9818e75c)
            )
        );
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(0),
            abi.encode(
                address(0x3af3563Ba5C68EB7DCbAdd2dF0FcE4CC9818e75c),
                _beefyBooster,
                _beefyWithdrawalFee
            )
        );

        // Using stMATIC-MATIC vault Booster on polygon
        vm.expectRevert(
            abi.encodeWithSelector(
                BeefyAdapter.InvalidBeefyBooster.selector,
                address(0xBb77dDe3101B8f9B71755ABe2F69b64e79AE4A41)
            )
        );
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(0),
            abi.encode(
                _beefyVault,
                address(0xBb77dDe3101B8f9B71755ABe2F69b64e79AE4A41),
                _beefyWithdrawalFee
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
    function test__RT_deposit_withdraw() public override {
        _mintFor(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);
        uint256 shares2 = adapter.withdraw(defaultAmount - 1, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(shares2, shares1, _delta_, testId);
    }

    // NOTE - The beefy adapter suffers often from an off-by-one error which "steals" 1 wei from the user
    function test__RT_mint_withdraw() public override {
        _mintFor(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(defaultAmount, bob);
        uint256 shares = adapter.withdraw(assets - 1, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(shares, defaultAmount, _delta_, testId);
    }
}
