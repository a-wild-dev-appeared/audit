// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {MockERC20} from "./utils/mocks/MockERC20.sol";
import {MultiRewardEscrow, IERC20} from "../utils/MultiRewardEscrow.sol";
import {IContractRegistry} from "../interfaces/IContractRegistry.sol";
import {IACLRegistry} from "../interfaces/IACLRegistry.sol";
import {KeeperIncentiveV2, IKeeperIncentiveV2} from "../utils/KeeperIncentiveV2.sol";

address constant CONTRACT_REGISTRY = 0x85831b53AFb86889c20aF38e654d871D8b0B7eC3;
address constant ACL_REGISTRY = 0x8A41aAa4B467ea545DDDc5759cE3D35984F093f4;
address constant ACL_ADMIN = 0x92a1cB552d0e177f3A135B4c87A4160C8f2a485f;

contract MultiRewardEscrowTest is Test {
    MockERC20 token1;
    MockERC20 token2;
    IERC20 iToken1;
    IERC20 iToken2;

    KeeperIncentiveV2 keeperIncentive;

    MultiRewardEscrow escrow;

    address alice = address(0xABCD);
    address bob = address(0xDCBA);
    address feeRecipient = address(0x9999);

    event Locked(
        IERC20 indexed token,
        address indexed account,
        uint256 amount,
        uint256 duration,
        uint256 offset
    );

    event RewardsClaimed(
        IERC20 indexed token,
        address indexed account,
        uint256 amount
    );

    event FeeSet(IERC20 indexed token, uint256 amount);
    event KeeperPercUpdated(uint256 oldPerc, uint256 newPerc);
    event FeeClaimed(IERC20 indexed token, uint256 amount);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("ETH_RPC_URL"));
        vm.selectFork(forkId);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(feeRecipient, "feeRecipient");

        token1 = new MockERC20("Mock Token1", "TKN1", 18);
        token2 = new MockERC20("Mock Token2", "TKN2", 18);

        iToken1 = IERC20(address(token1));
        iToken2 = IERC20(address(token2));

        keeperIncentive = new KeeperIncentiveV2(
            IContractRegistry(CONTRACT_REGISTRY),
            0,
            0
        );

        escrow = new MultiRewardEscrow(
            address(this),
            IKeeperIncentiveV2(address(keeperIncentive)),
            feeRecipient
        );

        token1.mint(alice, 10 ether);
        token2.mint(alice, 10 ether);

        vm.startPrank(alice);
        token1.approve(address(escrow), 10 ether);
        token2.approve(address(escrow), 10 ether);
        vm.stopPrank();

        vm.startPrank(ACL_ADMIN);
        IACLRegistry(ACL_REGISTRY).grantRole(
            keccak256("INCENTIVE_MANAGER_ROLE"),
            ACL_ADMIN
        );

        IContractRegistry(CONTRACT_REGISTRY).addContract(
            keccak256("FeeRecipient"),
            feeRecipient,
            keccak256("1")
        );
        IContractRegistry(CONTRACT_REGISTRY).updateContract(
            keccak256("KeeperIncentive"),
            address(keeperIncentive),
            keccak256("2")
        );

        // Create incentive with any token. We use `tip()` anyways
        keeperIncentive.createIncentive(
            address(escrow),
            1,
            false,
            true,
            address(token1),
            1,
            0
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            LOCK LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__lock() public {
        vm.startPrank(alice);

        vm.expectEmit(false, false, false, true, address(escrow));
        emit Locked(iToken1, alice, 10 ether, 100, 0);

        uint256 aliceLockTime = block.timestamp;
        escrow.lock(iToken1, alice, 10 ether, 100, 0);

        vm.expectEmit(false, false, false, true, address(escrow));
        emit Locked(iToken2, bob, 10 ether, 100, 10);

        uint256 bobLockTime = block.timestamp;
        escrow.lock(iToken2, bob, 10 ether, 100, 10);
        vm.stopPrank();

        // Check Alice's Escrow
        bytes32[] memory aliceEscrowIds = escrow.getEscrowIdsByUser(alice);
        MultiRewardEscrow.Escrow[] memory aliceEscrows = escrow.getEscrows(
            aliceEscrowIds
        );

        assertEq(address(aliceEscrows[0].token), address(token1));
        assertEq(aliceEscrows[0].start, aliceLockTime);
        assertEq(aliceEscrows[0].lastUpdateTime, aliceLockTime);
        assertEq(aliceEscrows[0].end, aliceLockTime + 100);
        assertEq(aliceEscrows[0].balance, 10 ether);
        assertEq(aliceEscrows[0].initialBalance, 10 ether);
        assertEq(aliceEscrows[0].account, alice);

        // Check Bob's Escrow
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        MultiRewardEscrow.Escrow[] memory bobEscrows = escrow.getEscrows(
            bobEscrowIds
        );

        uint256 start = bobLockTime + 10;
        assertEq(address(bobEscrows[0].token), address(token2));
        assertEq(bobEscrows[0].start, start);
        assertEq(bobEscrows[0].lastUpdateTime, start);
        assertEq(bobEscrows[0].end, start + 100);
        assertEq(bobEscrows[0].balance, 10 ether);
        assertEq(bobEscrows[0].initialBalance, 10 ether);
        assertEq(bobEscrows[0].account, bob);
    }

    function testFail__lock_has_no_token() public {
        vm.prank(alice);
        escrow.lock(IERC20(address(0)), bob, 10 ether, 100, 0);
    }

    function testFail__lock_has_no_account() public {
        vm.prank(alice);
        escrow.lock(iToken1, address(0), 10 ether, 100, 0);
    }

    function testFail__lock_has_no_amount() public {
        vm.prank(alice);
        escrow.lock(iToken1, address(0), 0, 100, 0);
    }

    function testFail__lock_has_no_duration() public {
        vm.prank(alice);
        escrow.lock(iToken1, alice, 10 ether, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function _lockFunds() internal {
        vm.startPrank(alice);
        escrow.lock(iToken1, bob, 10 ether, 10, 0);
        escrow.lock(iToken2, bob, 10 ether, 100, 0);
        vm.stopPrank();
    }

    function test__claim() public {
        _lockFunds();
        vm.warp(block.timestamp + 10);

        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.prank(bob);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit RewardsClaimed(iToken1, bob, 10 ether);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit RewardsClaimed(iToken2, bob, 1 ether);

        uint256 bobClaimTime = block.timestamp;
        escrow.claimRewards(bobEscrowIds);

        assertEq(token1.balanceOf(bob), 10 ether);
        assertEq(token2.balanceOf(bob), 1 ether);

        MultiRewardEscrow.Escrow[] memory bobEscrows = escrow.getEscrows(
            bobEscrowIds
        );

        assertEq(bobEscrows[0].lastUpdateTime, bobClaimTime);
        assertEq(bobEscrows[0].balance, 0);
        assertEq(bobEscrows[1].lastUpdateTime, bobClaimTime);
        assertEq(bobEscrows[1].balance, 9 ether);
    }

    function testFail__zero_claim() public {
        _lockFunds();

        vm.warp(block.timestamp + 10);

        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.startPrank(bob);
        escrow.claimRewards(bobEscrowIds);

        vm.expectRevert(MultiRewardEscrow.NotClaimable.selector);
        escrow.claimRewards(bobEscrowIds);
    }

    function test__claim_for_other_user() public {
        _lockFunds();
        vm.warp(block.timestamp + 10);

        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.prank(alice);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit RewardsClaimed(iToken1, bob, 10 ether);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit RewardsClaimed(iToken2, bob, 1 ether);

        escrow.claimRewards(bobEscrowIds);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getFeeSettings()
        internal
        view
        returns (IERC20[] memory tokens, uint256[] memory fees)
    {
        tokens = new IERC20[](2);
        tokens[0] = iToken1;
        tokens[1] = iToken2;
        fees = new uint256[](2);
        fees[0] = 1e14;
        fees[1] = 1e16;
    }

    function test__setFees() public {
        (IERC20[] memory tokens, uint256[] memory fees) = _getFeeSettings();

        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeSet(iToken1, 1e14);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeSet(iToken2, 1e16);
        escrow.setFees(tokens, fees);

        (, uint256 feePerc) = escrow.fees(iToken1);
        assertEq(feePerc, 1e14);

        (, feePerc) = escrow.fees(iToken2);
        assertEq(feePerc, 1e16);
    }

    function testFail__setFees_nonOwner() public {
        (IERC20[] memory tokens, uint256[] memory fees) = _getFeeSettings();

        vm.prank(alice);
        escrow.setFees(tokens, fees);
    }

    function testFail__setFees_non_matching_arrays() public {
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory fees = new uint256[](1);

        escrow.setFees(tokens, fees);
    }

    function test__setKeeperPerc() public {
        vm.expectEmit(false, false, false, true, address(escrow));
        emit KeeperPercUpdated(0, 1e16);
        escrow.setKeeperPerc(1e16);

        assertEq(escrow.keeperPerc(), 1e16);
    }

    function testFail__setKeeperPerc_nonOwner() public {
        vm.prank(alice);
        escrow.setKeeperPerc(1e16);
    }

    function testFail__setKeeperPerc_InvalidPerc() public {
        escrow.setKeeperPerc(1e19);
    }

    function test__take_fees() public {
        (IERC20[] memory tokens, uint256[] memory fees) = _getFeeSettings();
        escrow.setFees(tokens, fees);
        _lockFunds();

        uint256 expectedFee1 = Math.mulDiv(10 ether, 1e14, 1e18);
        uint256 expectedFee2 = Math.mulDiv(10 ether, 1e16, 1e18);

        // Check Bob's Escrow
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        MultiRewardEscrow.Escrow[] memory bobEscrows = escrow.getEscrows(
            bobEscrowIds
        );

        assertEq(bobEscrows[0].balance, 10 ether - expectedFee1);
        assertEq(bobEscrows[0].initialBalance, 10 ether - expectedFee1);
        assertEq(bobEscrows[1].balance, 10 ether - expectedFee2);
        assertEq(bobEscrows[1].initialBalance, 10 ether - expectedFee2);

        (uint256 accrued, ) = escrow.fees(iToken1);
        assertEq(accrued, expectedFee1);

        (accrued, ) = escrow.fees(iToken2);
        assertEq(accrued, expectedFee2);
    }

    function test__claimFees() public {
        (IERC20[] memory tokens, uint256[] memory fees) = _getFeeSettings();
        escrow.setFees(tokens, fees);
        escrow.setKeeperPerc(1e15);
        _lockFunds();

        uint256 expectedFee1 = Math.mulDiv(10 ether, 1e14, 1e18);
        uint256 expectedFee2 = Math.mulDiv(10 ether, 1e16, 1e18);

        uint256 tipAmount1 = Math.mulDiv(expectedFee1, 1e15, 1e18);
        uint256 tipAmount2 = Math.mulDiv(expectedFee2, 1e15, 1e18);

        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeClaimed(IERC20(address(token1)), expectedFee1 - tipAmount1);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit FeeClaimed(IERC20(address(token2)), expectedFee2 - tipAmount2);
        escrow.claimFees(tokens);

        assertEq(token1.balanceOf(feeRecipient), expectedFee1 - tipAmount1);
        assertEq(token2.balanceOf(feeRecipient), expectedFee2 - tipAmount2);

        assertEq(token1.balanceOf(address(keeperIncentive)), tipAmount1);
        assertEq(token2.balanceOf(address(keeperIncentive)), tipAmount2);
    }

    function testFail__claimFees_no_fees() public {
        (IERC20[] memory tokens, ) = _getFeeSettings();
        escrow.claimFees(tokens);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

    function test__getEscrowIdsByUser() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        assertEq(bobEscrowIds.length, 2);
    }

    function test__getEscrowIdsByUser_no_escrows() public {
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        assertEq(bobEscrowIds.length, 0);
    }

    function test__getEscrowIdsByUser_no_user() public {
        bytes32[] memory emptyEscrowIds = escrow.getEscrowIdsByUser(
            address(0x4444)
        );
        assertEq(emptyEscrowIds.length, 0);
    }

    function test__getEscrowIdsByUserAndToken() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUserAndToken(
            bob,
            iToken1
        );
        assertEq(bobEscrowIds.length, 1);
    }

    function test__getEscrowIdsByUserAndToken_no_escrows() public {
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUserAndToken(
            bob,
            iToken1
        );
        assertEq(bobEscrowIds.length, 0);
    }

    function test__getEscrowIdsByUserAndToken_no_user() public {
        bytes32[] memory emptyEscrowIds = escrow.getEscrowIdsByUserAndToken(
            address(0),
            iToken1
        );
        assertEq(emptyEscrowIds.length, 0);
    }

    function test__getEscrowIdsByUserAndToken_no_token() public {
        bytes32[] memory emptyEscrowIds = escrow.getEscrowIdsByUserAndToken(
            bob,
            IERC20(address(0))
        );
        assertEq(emptyEscrowIds.length, 0);
    }

    function test__getEscrows() public {
        _lockFunds();

        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        MultiRewardEscrow.Escrow[] memory bobEscrows = escrow.getEscrows(
            bobEscrowIds
        );
        assertEq(bobEscrows.length, 2);
    }

    function test__getEscrows_multiple_user() public {
        vm.startPrank(alice);
        escrow.lock(iToken1, bob, 10 ether, 10, 0);
        escrow.lock(iToken2, alice, 10 ether, 100, 0);
        vm.stopPrank();

        bytes32[] memory escrowIds = new bytes32[](2);
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);
        bytes32[] memory aliceEscrowIds = escrow.getEscrowIdsByUser(alice);
        escrowIds[0] = bobEscrowIds[0];
        escrowIds[1] = aliceEscrowIds[0];

        MultiRewardEscrow.Escrow[] memory escrows = escrow.getEscrows(
            escrowIds
        );
        assertEq(escrows.length, 2);
        assertEq(escrows[0].account, bob);
        assertEq(escrows[1].account, alice);
    }

    function test__getEscrows_no_ids() public {
        bytes32[] memory escrowIds = new bytes32[](1);
        MultiRewardEscrow.Escrow[] memory escrows = escrow.getEscrows(
            escrowIds
        );

        assertEq(escrows.length, 1);

        assertEq(address(escrows[0].token), address(0));
        assertEq(escrows[0].start, 0);
        assertEq(escrows[0].lastUpdateTime, 0);
        assertEq(escrows[0].end, 0);
        assertEq(escrows[0].balance, 0);
        assertEq(escrows[0].initialBalance, 0);
        assertEq(escrows[0].account, address(0));
    }

    function test__isClaimable() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        assertTrue(escrow.isClaimable(bobEscrowIds[0]));
        assertTrue(escrow.isClaimable(bobEscrowIds[1]));
    }

    function test__isClaimable_no_balance() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.warp(block.timestamp + 10);

        vm.prank(bob);
        escrow.claimRewards(bobEscrowIds);

        assertFalse(escrow.isClaimable(bobEscrowIds[0]));
        assertTrue(escrow.isClaimable(bobEscrowIds[1]));
    }

    function test__isClaimable_no_escrow() public {
        bytes32[] memory escrowIds = new bytes32[](1);

        assertFalse(escrow.isClaimable(escrowIds[0]));
    }

    function test__getClaimableAmount() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.warp(block.timestamp + 10);

        assertEq(escrow.getClaimableAmount(bobEscrowIds[0]), 10 ether);
        assertEq(escrow.getClaimableAmount(bobEscrowIds[1]), 1 ether);
    }

    function test__getClaimableAmount_after_claim() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.warp(block.timestamp + 10);

        vm.prank(bob);
        escrow.claimRewards(bobEscrowIds);

        assertEq(escrow.getClaimableAmount(bobEscrowIds[0]), 0 ether);
    }

    function test__getClaimableAmount_partial_claim() public {
        _lockFunds();
        bytes32[] memory bobEscrowIds = escrow.getEscrowIdsByUser(bob);

        vm.warp(block.timestamp + 10);

        vm.prank(bob);
        escrow.claimRewards(bobEscrowIds);

        assertEq(escrow.getClaimableAmount(bobEscrowIds[1]), 0 ether);

        vm.warp(block.timestamp + 10);

        assertEq(escrow.getClaimableAmount(bobEscrowIds[1]), 1 ether);

        vm.warp(block.timestamp + 10);

        assertEq(escrow.getClaimableAmount(bobEscrowIds[1]), 2 ether);
    }

    function test__getClaimableAmount_no_escrow() public {
        bytes32[] memory escrowIds = new bytes32[](1);
        assertEq(escrow.getClaimableAmount(escrowIds[0]), 0 ether);
    }
}
