// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {PropertyTest} from "./PropertyTest.prop.sol";
import {IAdapter, IERC4626} from "../../../../interfaces/vault/IAdapter.sol";
import {IStrategy} from "../../../../interfaces/vault/IStrategy.sol";
import {IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ITestConfigStorage} from "./ITestConfigStorage.sol";
import {MockStrategy} from "../../../utils/mocks/MockStrategy.sol";

contract AbstractAdapterTest is PropertyTest {
    ITestConfigStorage testConfigStorage;

    string baseTestId; // Depends on external Protocol (e.g. Beefy,Yearn...)
    string testId; // baseTestId + Asset

    bytes32 constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    address bob = address(1);
    address alice = address(2);
    address feeRecipient = address(0x4444);

    uint256 defaultAmount;
    uint256 raise;

    uint256 maxAssets;
    uint256 maxShares;

    IERC20 asset;
    IAdapter adapter;
    IStrategy strategy;
    address externalRegistry;

    bytes4[8] sigs;

    function setUpBaseTest(
        IERC20 asset_,
        IAdapter adapter_,
        address externalRegistry_,
        uint256 delta_,
        string memory baseTestId_,
        bool useStrategy_
    ) public {
        // Setup PropertyTest
        _asset_ = address(asset_);
        _vault_ = address(adapter_);
        _delta_ = delta_;

        asset = asset_;
        adapter = adapter_;
        externalRegistry = externalRegistry_;

        defaultAmount = 10**IERC20Metadata(address(asset_)).decimals();

        raise = defaultAmount * 100_000;
        maxAssets = defaultAmount * 1000;
        maxShares = maxAssets / 2;

        baseTestId = baseTestId_;
        testId = string.concat(
            baseTestId_,
            IERC20Metadata(address(asset)).symbol()
        );

        if (useStrategy_) strategy = IStrategy(address(new MockStrategy()));
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // NOTE: You MUST override these

    // Its should use exactly setup to override the previous setup
    function overrideSetup(bytes memory testConfig) public virtual {
        // setUpBasetest();
        // protocol specific setup();
    }

    // Construct a new Adapter and set it to `adapter`
    function createAdapter() public virtual {}

    // Increase the pricePerShare of the external protocol
    // sometimes its enough to simply add assets, othertimes one also needs to call some functions before the external protocol reflects the change
    function increasePricePerShare(uint256 amount) public virtual {}

    // Check the balance of the external protocol held by the adapter
    // Most of the time this should be a simple `balanceOf` call to the external protocol but some might have different implementations
    function iouBalance() public view virtual returns (uint256) {
        // extProt.balanceOf(address(adapter))
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public virtual {}

    function verify_adapterInit() public virtual {}

    function _mintFor(uint256 amount, address receiver) internal {
        deal(address(asset), receiver, amount);

        vm.prank(receiver);
        asset.approve(address(adapter), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    event SelectorsVerified();
    event AdapterVerified();
    event StrategySetup();
    event Initialized(uint8 version);

    function test__initialization() public virtual {
        createAdapter();
        uint256 callTime = block.timestamp;

        if (address(strategy) != address(0)) {
            vm.expectEmit(false, false, false, true, address(strategy));
            emit SelectorsVerified();
            vm.expectEmit(false, false, false, true, address(strategy));
            emit AdapterVerified();
            vm.expectEmit(false, false, false, true, address(strategy));
            emit StrategySetup();
        }
        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
        );

        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(strategy), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(adapter.feesUpdatedAt(), callTime, "feesUpdatedAt");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals(),
            "decimals"
        );

        verify_adapterInit();
    }

    /*//////////////////////////////////////////////////////////////
                          GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

    // OPTIONAL
    function test__rewardsTokens() public virtual {}

    function test__asset() public virtual {
        prop_asset();
    }

    function test__totalAssets() public virtual {
        prop_totalAssets();
        verify_totalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                          CONVERSION VIEWS
    //////////////////////////////////////////////////////////////*/

    function test__convertToShares() public virtual {
        prop_convertToShares(bob, alice, defaultAmount);
    }

    function test__convertToAssets() public virtual {
        prop_convertToAssets(bob, alice, defaultAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

    // NOTE: These Are just prop tests currently. Override tests here if the adapter has unique max-functions which override AdapterBase.sol

    function test__maxDeposit() public virtual {
        prop_maxDeposit(bob);

        // Deposit smth so withdraw on pause is not 0
        deal(address(asset), address(this), defaultAmount);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        adapter.pause();
        assertEq(adapter.maxDeposit(bob), 0);
    }

    function test__maxMint() public virtual {
        prop_maxMint(bob);

        // Deposit smth so withdraw on pause is not 0
        deal(address(asset), address(this), defaultAmount);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        adapter.pause();
        assertEq(adapter.maxMint(bob), 0);
    }

    function test__maxWithdraw() public virtual {
        prop_maxWithdraw(bob);
    }

    function test__maxRedeem() public virtual {
        prop_maxRedeem(bob);
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW VIEWS
    //////////////////////////////////////////////////////////////*/
    function test__previewDeposit(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxAssets);

        deal(address(asset), bob, maxAssets);
        vm.prank(bob);
        asset.approve(address(adapter), maxAssets);

        prop_previewDeposit(bob, bob, amount, testId);
    }

    function test__previewMint(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxShares);

        deal(address(asset), bob, maxAssets);
        vm.prank(bob);
        asset.approve(address(adapter), maxAssets);

        prop_previewMint(bob, bob, amount, testId);
    }

    function test__previewWithdraw(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxAssets);

        uint256 reqAssets = (adapter.previewMint(
            adapter.previewWithdraw(amount)
        ) * 10) / 9;
        _mintFor(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        prop_previewWithdraw(bob, bob, bob, amount, testId);
    }

    function test__previewRedeem(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxShares);

        uint256 reqAssets = (adapter.previewMint(amount) * 10) / 9;
        _mintFor(reqAssets, bob);
        vm.prank(bob);
        adapter.deposit(reqAssets, bob);

        prop_previewRedeem(bob, bob, bob, amount, testId);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__deposit(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxAssets);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            _mintFor(amount, bob);
            prop_deposit(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintFor(amount, bob);
            prop_deposit(bob, alice, amount, testId);
        }
    }

    function test__mint(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxShares);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            _mintFor(adapter.previewMint(amount), bob);
            prop_mint(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintFor(adapter.previewMint(amount), bob);
            prop_mint(bob, alice, amount, testId);
        }
    }

    function test__withdraw(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxAssets);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = (adapter.previewMint(
                adapter.previewWithdraw(amount)
            ) * 10) / 9;
            _mintFor(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);
            prop_withdraw(bob, bob, amount, testId);

            _mintFor(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_withdraw(alice, bob, amount, testId);
        }
    }

    function test__redeem(uint8 fuzzAmount) public virtual {
        uint256 amount = bound(uint256(fuzzAmount), 10, maxShares);
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

            uint256 reqAssets = (adapter.previewMint(amount) * 10) / 9;
            _mintFor(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);
            prop_redeem(bob, bob, amount, testId);

            _mintFor(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, amount, testId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ROUNDTRIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test__RT_deposit_redeem() public virtual {
        _mintFor(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares = adapter.deposit(defaultAmount, bob);
        uint256 assets = adapter.redeem(shares, bob, bob);
        vm.stopPrank();

        assertApproxLeAbs(assets, defaultAmount, _delta_, testId);
    }

    function test__RT_deposit_withdraw() public virtual {
        _mintFor(defaultAmount, bob);

        vm.startPrank(bob);
        uint256 shares1 = adapter.deposit(defaultAmount, bob);
        uint256 shares2 = adapter.withdraw(defaultAmount, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(shares2, shares1, _delta_, testId);
    }

    function test__RT_mint_withdraw() public virtual {
        _mintFor(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets = adapter.mint(defaultAmount, bob);
        uint256 shares = adapter.withdraw(assets, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(shares, defaultAmount, _delta_, testId);
    }

    function test__RT_mint_redeem() public virtual {
        _mintFor(adapter.previewMint(defaultAmount), bob);

        vm.startPrank(bob);
        uint256 assets1 = adapter.mint(defaultAmount, bob);
        uint256 assets2 = adapter.redeem(defaultAmount, bob, bob);
        vm.stopPrank();

        assertApproxGeAbs(assets2, assets1, _delta_, testId);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE
    //////////////////////////////////////////////////////////////*/

    function test__pause() public virtual {
        _mintFor(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            oldTotalAssets,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert("ERC4626: deposit more than max");
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert("ERC4626: mint more than max");
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }

    function testFail__pause_nonOwner() public virtual {
        vm.prank(alice);
        adapter.pause();
    }

    function test__unpause() public virtual {
        _mintFor(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }

    function testFail__unpause_nonOwner() public virtual {
        adapter.pause();

        vm.prank(alice);
        adapter.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    event StrategyExecuted();
    event Harvested();

    function test__harvest() public virtual {
        _mintFor(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        // Skip a year
        vm.warp(block.timestamp + 365.25 days);

        uint256 expectedFee = adapter.convertToShares(
            (defaultAmount * 5e16) / 1e18
        );
        uint256 callTime = block.timestamp;

        if (address(strategy) != address(0)) {
            vm.expectEmit(false, false, false, true, address(adapter));
            emit StrategyExecuted();
        }
        vm.expectEmit(false, false, false, true, address(adapter));
        emit Harvested();

        adapter.harvest();

        assertEq(adapter.feesUpdatedAt(), callTime, "feesUpdatedAt");
        assertApproxEqAbs(
            adapter.assetsCheckpoint(),
            defaultAmount,
            _delta_,
            "assetsCheckpoint"
        );
        assertApproxEqAbs(
            adapter.totalSupply(),
            defaultAmount + expectedFee,
            _delta_,
            "totalSupply"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT FEE
    //////////////////////////////////////////////////////////////*/

    event ManagementFeeChanged(uint256 oldFee, uint256 newFee);

    function test__setManagementFee() public virtual {
        vm.expectEmit(false, false, false, true, address(adapter));
        emit ManagementFeeChanged(5e16, 1e16);
        adapter.setManagementFee(1e16);

        assertEq(adapter.managementFee(), 1e16);
    }

    function testFail__setManagementFee_nonOwner() public virtual {
        vm.prank(alice);
        adapter.setManagementFee(1e16);
    }

    function testFail__setManagementFee_invalid_fee() public virtual {
        adapter.setManagementFee(1e17);
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    // OPTIONAL
    function testClaim() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

    function testPermit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    adapter.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        adapter.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(adapter.allowance(owner, address(0xCAFE)), 1e18, "allowance");
        assertEq(adapter.nonces(owner), 1, "nonce");
    }
}
