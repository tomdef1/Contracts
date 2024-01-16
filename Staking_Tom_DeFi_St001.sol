// SPDX-License-Identifier: MIT

/* 
@d3ploy - all points actioned apart from below:
#7 - Using 0.8.20 as supported by BNB Chain
#10 - Implemented where appropriate
#13 - Implementing NatSpec in final deployed code as to keep working version easier to manage
#14 - Code removed
#16 - Added immutable where relevant
*/

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
using SafeERC20 for IERC20;

// Declaring the contract
contract Staking_Tom_DeFi_St001 is ReentrancyGuard {
    // State variables
    IERC20 public immutable stakingToken;            // Token users will stake
    IERC20 public immutable rewardToken;             // Token users will earn as rewards
    address public proposedOwner;          // Two-Step Validation in Critical Address Change
    address public owner;                  // Owner of the contract
    uint256 public lockupPeriod;           // Time that must pass before stakers can withdraw
    uint256 public stakingPeriodLength;    // Total length of the staking period
    bool public stakingActive;             // Indicates if the staking period is currently active
    uint256 public startTime;              // When the current staking period started
    uint256 public totalStaked;            // Total amount of tokens staked
    uint256 public totalRewards;           // Total amount of rewards to distribute
    uint256 public rewardsDistributed;     // Total rewards distributed so far

    // Mappings with 0.8.18 mapping update
    mapping(address => uint256) public stakes; // Maps an address to the amount staked
    mapping(address => uint256) public lastStakedTime; // Maps an address to the last staking timestamp
    mapping(address => uint256) public rewards; // Maps an address to the reward amount
    mapping(address => bool) public isController; // Maps an address to a boolean indicating if it is an authorized controller

    // Events
    event Staked(address indexed user, uint256 amount, uint256 total);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StakingPeriodEnded(uint256 remainingRewards);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    constructor(
        uint256 _stakingPeriodLength,
        uint256 _lockupPeriod,
        address _stakingToken,
        address _rewardToken,
        uint256 _totalRewards
    ) {
        require(_stakingToken != address(0), "Staking token cannot be the zero address");
        require(_rewardToken != address(0), "Reward token cannot be the zero address");

        owner = msg.sender;                   
        stakingPeriodLength = _stakingPeriodLength;
        lockupPeriod = _lockupPeriod;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        totalRewards = _totalRewards;
    }

    // Functions

    // Starts the staking period
    function start() external onlyOwner {
        require(!stakingActive, "Staking already started");
        // Check if the contract has enough reward tokens
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        require(totalRewards <= rewardBalance, "Insufficient reward tokens in contract");

        stakingActive = true;
        startTime = block.timestamp;
        rewardsDistributed = 0;
    }

    // Allows users to stake tokens
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        // Check if staking is within the lockup period
        require(block.timestamp < startTime + lockupPeriod, "Staking period has ended or lockup period has passed");
        require(stakingActive, "Staking is not active");

        // Use safeTransferFrom for token transfer
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (stakingActive && stakes[msg.sender] > 0) {
            rewards[msg.sender] += calculateReward(msg.sender);
        }

        stakes[msg.sender] += amount;
        totalStaked = totalStaked + amount;
        lastStakedTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount, stakes[msg.sender]);
    }

    // Allows users to withdraw their staked tokens
    function withdraw(uint256 amount) external nonReentrant {
        require(stakes[msg.sender] >= amount, "Withdrawing more than you have!");
        require(block.timestamp - lastStakedTime[msg.sender] > lockupPeriod, "Lockup period not yet passed");

        // Calculate rewards irrespective of whether staking is currently active
        rewards[msg.sender] += calculateReward(msg.sender);
        stakes[msg.sender] -= amount;
        totalStaked = totalStaked - amount;

        // Use safeTransfer for token transfer
        stakingToken.safeTransfer(msg.sender, amount);

        // Reset the last staked time to the current time to stop further reward accrual
        lastStakedTime[msg.sender] = block.timestamp;
        emit Withdrawn(msg.sender, amount);
    }

    // Allows users to claim their rewards
    function claimRewards() external nonReentrant {
        if (stakingActive) {
            rewards[msg.sender] += calculateReward(msg.sender);
        }
        
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0; // Prevent re-entrancy attack
            rewardsDistributed += reward;

            // Use safeTransfer for token transfer
            rewardToken.safeTransfer(msg.sender, reward
            );
        emit RewardPaid(msg.sender, reward);
        }
    }

    // Internal function to calculate rewards
    function calculateReward(address user) internal view returns (uint256) {
        uint256 stakedAmount = stakes[user];
        if (stakedAmount == 0) {
            return 0;
        }
        uint256 timeStaked = stakingActive ? block.timestamp - lastStakedTime[user] : stakingPeriodLength;
        uint256 reward = (stakedAmount * timeStaked * totalRewards) / (totalStaked * stakingPeriodLength);
        return reward;
    }

    // Ends the current staking period
    function endStakingPeriod() external onlyOwner {
        require(stakingActive, "Staking inactive");
        stakingActive = false;

        uint256 remainingRewards = totalRewards - rewardsDistributed;
        // You might want to handle or transfer the remaining rewards here

        emit StakingPeriodEnded(remainingRewards);
    }


    // Proposes a new owner, requires confirmation by the new owner
    function proposeOwnership(address _proposedOwner) external onlyOwner {
        require(_proposedOwner != address(0), "Proposed owner is the zero address");
        require(_proposedOwner != owner, "Proposed owner is already the owner");
        proposedOwner = _proposedOwner;
    }

    // New owner claims ownership
    function claimOwnership() external {
        require(msg.sender == proposedOwner, "Caller isnot the proposed owner");
        emit OwnershipTransferred(owner, proposedOwner);
        owner = proposedOwner;
        proposedOwner = address(0);
    }

    // Allows the owner to set a new lockup period
    function setLockupPeriod(uint256 newLockupPeriod) external onlyOwner {
        require(newLockupPeriod <= lockupPeriod, "New period <= current");
        lockupPeriod = newLockupPeriod;
    }

    // Allows the owner to set a new staking period length
    function setStakingPeriodLength(uint256 newLength) external onlyOwner {
        stakingPeriodLength = newLength;
    }

    // Read function to get the remaining time of the staking period
    function getTimeLeft() public view returns (uint256) {
        if (stakingActive) {
            uint256 timePassed = block.timestamp - startTime;
            if (timePassed < stakingPeriodLength) {
                return stakingPeriodLength - timePassed;
            } else {
                return 0; // Staking period has ended
            }
        } else {
            return 0; // Staking period is not active
        }
    }

    // Read function to get the rewards earned in the current period by a user
    function getCurrentPeriodRewards(address user) public view returns (uint256) {
        if (stakingActive) {
            return calculateReward(user);
        } else {
            return 0; // No rewards if staking period is not active
        }
    }

    // Read function to get the total rewards earned by a user across all periods
    function getTotalRewardsEarned(address user) public view returns (uint256) {
        return rewards[user] + getCurrentPeriodRewards(user);
    }

    // Read function to get the amount a user is entitled to withdraw
    function getWithdrawableAmount(address user) public view returns (uint256) {
        if (block.timestamp - lastStakedTime[user] > lockupPeriod) {
            return stakes[user];
        } else {
            return 0; // Nothing withdrawable if within the lockup period
        }
    }

    // Read function to get all current staking parameters
    function getStakingParameters() public view returns (
        uint256 _lockupPeriod, 
        uint256 _stakingPeriodLength, 
        uint256 _totalStaked, 
        uint256 _totalRewards, 
        uint256 _rewardsDistributed, 
        bool _stakingActive, 
        uint256 _timeLeft
    ) {
        return (
            lockupPeriod, 
            stakingPeriodLength, 
            totalStaked, 
            totalRewards, 
            rewardsDistributed, 
            stakingActive, 
            getTimeLeft()
        );
    }
}
