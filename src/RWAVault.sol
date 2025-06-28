// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import {AccessControl} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";
import {Pausable} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/security/Pausable.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import "./RWAToken.sol";
import "./RWAManager.sol";

/**
 * @title RWAVault
 * @notice Advanced yield and reward distribution vault for RWA token holders
 * @dev Supports multiple reward tokens, cross-chain yield aggregation, and enhanced staking features
 */
contract RWAVault is  AccessControl, Pausable {
    
    using SafeERC20 for IERC20;
    
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    
    RWAToken public immutable rwaToken;
    RWAManager public immutable rwaManager;
    uint256 public immutable projectId;
    
    // Admin address stored for fee transfers
    address public admin;
    
    // Supported reward tokens
    mapping(address => bool) public supportedRewardTokens;
    mapping(address => uint8) public rewardTokenDecimals;
    address[] public rewardTokensList;
    
    struct UserStake {
        uint256 amount;
        mapping(address => uint256) rewardDebt; // rewardToken => debt
        uint256 stakedAt;
        uint256 lastClaimAt;
        uint256 totalRewardsClaimed;
        StakeType stakeType;
        uint256 lockEndTime; // For locked staking
    }
    
    struct RewardPool {
        uint256 accRewardPerShare; // Accumulated rewards per share, scaled by 1e12
        uint256 totalDistributed;
        uint256 lastDistributionTime;
        uint256 distributionCount;
    }
    
    struct RewardDistribution {
        address rewardToken;
        uint256 amount;
        uint256 timestamp;
        string description;
        address distributor;
        DistributionType distributionType;
    }
    
    enum StakeType {
        STANDARD,      // Regular staking
        LOCKED_30D,    // 30 days locked (1.1x multiplier)
        LOCKED_90D,    // 90 days locked (1.25x multiplier)
        LOCKED_365D,   // 365 days locked (1.5x multiplier)
        FOUNDER        // Founder/early investor special stake (2x multiplier)
    }
    
    enum DistributionType {
        RENTAL_INCOME,     // Property rental income
        ASSET_APPRECIATION, // Asset value gains
        DIVIDEND,          // Dividend payments
        BONUS,            // Special bonus distributions
        LIQUIDATION       // Asset liquidation proceeds
    }
    
    mapping(address => UserStake) public stakes;
    mapping(address => RewardPool) public rewardPools; // rewardToken => pool
    RewardDistribution[] public distributions;
    
    // Vault statistics
    uint256 public totalStaked;
    uint256 public totalStakers;
    uint256 public minStakeAmount = 1 * 1e18; // 1 RWA token minimum
    uint256 public stakingFee = 25; // 0.25% (basis points)
    uint256 public earlyUnstakeFee = 100; // 1% for early unstaking
    
    // Staking multipliers (basis points, 10000 = 1x)
    mapping(StakeType => uint256) public stakeMultipliers;
    
    // Yield tracking
    uint256 public totalYieldGenerated;
    uint256 public averageAPY; // Annual percentage yield (basis points)
    mapping(uint256 => uint256) public monthlyYield; // month => yield amount
    
    // Events
    event Staked(
        address indexed user,
        uint256 amount,
        StakeType stakeType,
        uint256 lockEndTime
    );
    
    event Unstaked(
        address indexed user,
        uint256 amount,
        uint256 penalty,
        address[] rewardTokens,
        uint256[] rewardAmounts
    );
    
    event RewardsClaimed(
        address indexed user,
        address[] rewardTokens,
        uint256[] amounts
    );
    
    event RewardsDistributed(
        address indexed distributor,
        address indexed rewardToken,
        uint256 amount,
        DistributionType distributionType,
        string description
    );
    
    event RewardTokenAdded(address indexed token, uint8 decimals);
    event RewardTokenRemoved(address indexed token);
    event StakeTypeUpdated(StakeType stakeType, uint256 multiplier);
    event VaultConfigUpdated(uint256 minStake, uint256 stakingFee, uint256 earlyUnstakeFee);
    
    // Errors
    error InsufficientStakeAmount();
    error NoStakeFound();
    error InsufficientStaked();
    error NotDistributor();
    error NoRewards();
    error UnsupportedRewardToken();
    error InvalidProject();
    error StakeLocked();
    error InvalidStakeType();
    error InvalidMultiplier();
    
    modifier validProject() {
        if (!rwaManager.isProjectInStatus(projectId, RWAManager.ProjectStatus.ACTIVE) && 
            !rwaManager.isProjectInStatus(projectId, RWAManager.ProjectStatus.COMPLETED)) {
            revert InvalidProject();
        }
        _;
    }
    
    modifier onlyStaker() {
        if (stakes[msg.sender].amount == 0) revert NoStakeFound();
        _;
    }

    constructor(
        address _rwaToken,
        address _rwaManager,
        uint256 _projectId,
        address _admin
    ) {
        require(_rwaToken != address(0), "Invalid RWA token");
        require(_rwaManager != address(0), "Invalid RWA manager");
        require(_admin != address(0), "Invalid admin");
        
        rwaToken = RWAToken(_rwaToken);
        rwaManager = RWAManager(_rwaManager);
        projectId = _projectId;
        admin = _admin;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        
        // Initialize stake multipliers
        stakeMultipliers[StakeType.STANDARD] = 10000;   // 1.0x
        stakeMultipliers[StakeType.LOCKED_30D] = 11000; // 1.1x
        stakeMultipliers[StakeType.LOCKED_90D] = 12500; // 1.25x
        stakeMultipliers[StakeType.LOCKED_365D] = 15000; // 1.5x
        stakeMultipliers[StakeType.FOUNDER] = 20000;    // 2.0x
        
        // Add ETH as default reward token
        supportedRewardTokens[address(0)] = true;
        rewardTokenDecimals[address(0)] = 18;
        rewardTokensList.push(address(0));
    }
    
    /**
     * @notice Stake RWA tokens with optional lock period
     */
    function stake(
        uint256 amount,
        StakeType stakeType
    ) external whenNotPaused validProject {
        if (amount < minStakeAmount) revert InsufficientStakeAmount();
        if (stakeType > StakeType.FOUNDER) revert InvalidStakeType();
        
        UserStake storage userStake = stakes[msg.sender];
        bool isNewStaker = userStake.amount == 0;
        
        // Claim pending rewards first if user already has stake
        if (!isNewStaker) {
            _claimAllRewards(msg.sender);
        }
        
        // Calculate staking fee
        uint256 fee = (amount * stakingFee) / 10000;
        uint256 stakeAmount = amount - fee;
        
        // Transfer tokens
        rwaToken.transferFrom(msg.sender, address(this), amount);
        
        // Calculate lock end time
        uint256 lockEndTime = 0;
        if (stakeType == StakeType.LOCKED_30D) {
            lockEndTime = block.timestamp + 30 days;
        } else if (stakeType == StakeType.LOCKED_90D) {
            lockEndTime = block.timestamp + 90 days;
        } else if (stakeType == StakeType.LOCKED_365D) {
            lockEndTime = block.timestamp + 365 days;
        }
        
        // Update user stake
        uint256 effectiveAmount = (stakeAmount * stakeMultipliers[stakeType]) / 10000;
        userStake.amount += effectiveAmount;
        userStake.stakedAt = block.timestamp;
        userStake.stakeType = stakeType;
        userStake.lockEndTime = lockEndTime;
        
        // Update reward debt for all reward tokens
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address rewardToken = rewardTokensList[i];
            userStake.rewardDebt[rewardToken] = 
                (userStake.amount * rewardPools[rewardToken].accRewardPerShare) / 1e12;
        }
        
        totalStaked += effectiveAmount;
        if (isNewStaker) {
            totalStakers++;
        }
        
        // Send fee to admin
        if (fee > 0) {
            rwaToken.transfer(admin, fee);
        }
        
        emit Staked(msg.sender, stakeAmount, stakeType, lockEndTime);
    }
    
    /**
     * @notice Unstake RWA tokens
     */
    function unstake(uint256 amount) external onlyStaker {
        UserStake storage userStake = stakes[msg.sender];
        
        if (amount > userStake.amount) revert InsufficientStaked();
        
        // Check if stake is locked
        if (userStake.lockEndTime > block.timestamp) {
            revert StakeLocked();
        }
        
        // Claim all pending rewards
        (address[] memory rewardTokens, uint256[] memory rewardAmounts) = _claimAllRewards(msg.sender);
        
        // Calculate early unstaking penalty if applicable
        uint256 penalty = 0;
        uint256 actualAmount = amount;
        
        if (userStake.stakeType != StakeType.STANDARD && 
            block.timestamp < userStake.stakedAt + _getLockDuration(userStake.stakeType)) {
            penalty = (amount * earlyUnstakeFee) / 10000;
            actualAmount = amount - penalty;
        }
        
        // Update stake
        userStake.amount -= amount;
        totalStaked -= amount;
        
        if (userStake.amount == 0) {
            totalStakers--;
        }
        
        // Update reward debt
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address rewardToken = rewardTokensList[i];
            userStake.rewardDebt[rewardToken] = 
                (userStake.amount * rewardPools[rewardToken].accRewardPerShare) / 1e12;
        }
        
        // Transfer tokens back (minus penalty)
        uint256 baseAmount = (actualAmount * 10000) / stakeMultipliers[userStake.stakeType];
        rwaToken.transfer(msg.sender, baseAmount);
        
        // Send penalty to admin if applicable
        if (penalty > 0) {
            uint256 basePenalty = (penalty * 10000) / stakeMultipliers[userStake.stakeType];
            rwaToken.transfer(admin, basePenalty);
        }
        
        emit Unstaked(msg.sender, actualAmount, penalty, rewardTokens, rewardAmounts);
    }
    
    /**
     * @notice Claim all pending rewards
     */
    function claimRewards() external onlyStaker {
        (address[] memory rewardTokens, uint256[] memory amounts) = _claimAllRewards(msg.sender);
        
        if (rewardTokens.length == 0) revert NoRewards();
        
        emit RewardsClaimed(msg.sender, rewardTokens, amounts);
    }
    
    /**
     * @notice Internal function to claim all rewards for a user
     */
    function _claimAllRewards(address user) internal returns (
        address[] memory rewardTokens,
        uint256[] memory amounts
    ) {
        UserStake storage userStake = stakes[user];
        
        if (userStake.amount == 0) return (new address[](0), new uint256[](0));
        
        uint256 rewardCount = 0;
        uint256[] memory tempAmounts = new uint256[](rewardTokensList.length);
        
        // Calculate rewards for each token
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address rewardToken = rewardTokensList[i];
            RewardPool storage pool = rewardPools[rewardToken];
            
            uint256 pending = (userStake.amount * pool.accRewardPerShare) / 1e12 - 
                             userStake.rewardDebt[rewardToken];
            
            if (pending > 0) {
                tempAmounts[i] = pending;
                rewardCount++;
                userStake.totalRewardsClaimed += pending;
            }
        }
        
        // Create arrays with only non-zero rewards
        rewardTokens = new address[](rewardCount);
        amounts = new uint256[](rewardCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            if (tempAmounts[i] > 0) {
                address rewardToken = rewardTokensList[i];
                rewardTokens[index] = rewardToken;
                amounts[index] = tempAmounts[i];
                
                // Transfer rewards
                if (rewardToken == address(0)) {
                    // ETH reward
                    payable(user).transfer(tempAmounts[i]);
                } else {
                    // ERC20 reward
                    IERC20(rewardToken).safeTransfer(user, tempAmounts[i]);
                }
                
                index++;
            }
        }
        
        // Update reward debt
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address rewardToken = rewardTokensList[i];
            userStake.rewardDebt[rewardToken] = 
                (userStake.amount * rewardPools[rewardToken].accRewardPerShare) / 1e12;
        }
        
        userStake.lastClaimAt = block.timestamp;
    }
    
    /**
     * @notice Distribute rewards to all stakers
     */
    function distributeRewards(
        address rewardToken,
        uint256 amount,
        DistributionType distributionType,
        string memory description
    ) external payable onlyRole(DISTRIBUTOR_ROLE) {
        if (!supportedRewardTokens[rewardToken]) revert UnsupportedRewardToken();
        if (totalStaked == 0) revert("No stakers");
        
        uint256 rewardAmount;
        
        if (rewardToken == address(0)) {
            // ETH reward
            rewardAmount = msg.value;
            require(rewardAmount > 0, "No ETH sent");
        } else {
            // ERC20 reward
            require(amount > 0, "Invalid amount");
            IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
            rewardAmount = amount;
        }
        
        // Update reward pool
        RewardPool storage pool = rewardPools[rewardToken];
        pool.accRewardPerShare += (rewardAmount * 1e12) / totalStaked;
        pool.totalDistributed += rewardAmount;
        pool.lastDistributionTime = block.timestamp;
        pool.distributionCount++;
        
        // Track total yield
        totalYieldGenerated += rewardAmount;
        monthlyYield[block.timestamp / 30 days] += rewardAmount;
        
        // Record distribution
        distributions.push(RewardDistribution({
            rewardToken: rewardToken,
            amount: rewardAmount,
            timestamp: block.timestamp,
            description: description,
            distributor: msg.sender,
            distributionType: distributionType
        }));
        
        emit RewardsDistributed(msg.sender, rewardToken, rewardAmount, distributionType, description);
    }
    
    /**
     * @notice Get pending rewards for a user
     */
    function getPendingRewards(address user) external view returns (
        address[] memory rewardTokens,
        uint256[] memory amounts
    ) {
        UserStake storage userStake = stakes[user];
        
        if (userStake.amount == 0) {
            return (new address[](0), new uint256[](0));
        }
        
        uint256 rewardCount = 0;
        uint256[] memory tempAmounts = new uint256[](rewardTokensList.length);
        
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address rewardToken = rewardTokensList[i];
            RewardPool storage pool = rewardPools[rewardToken];
            
            uint256 pending = (userStake.amount * pool.accRewardPerShare) / 1e12 - 
                             userStake.rewardDebt[rewardToken];
            
            if (pending > 0) {
                tempAmounts[i] = pending;
                rewardCount++;
            }
        }
        
        rewardTokens = new address[](rewardCount);
        amounts = new uint256[](rewardCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            if (tempAmounts[i] > 0) {
                rewardTokens[index] = rewardTokensList[i];
                amounts[index] = tempAmounts[i];
                index++;
            }
        }
    }
    
    /**
     * @notice Get user stake information
     */
    function getUserStakeInfo(address user) external view returns (
        uint256 stakedAmount,
        StakeType stakeType,
        uint256 lockEndTime,
        uint256 stakedAt,
        uint256 lastClaimAt,
        uint256 totalRewardsClaimed,
        bool isLocked
    ) {
        UserStake storage userStake = stakes[user];
        
        stakedAmount = userStake.amount;
        stakeType = userStake.stakeType;
        lockEndTime = userStake.lockEndTime;
        stakedAt = userStake.stakedAt;
        lastClaimAt = userStake.lastClaimAt;
        totalRewardsClaimed = userStake.totalRewardsClaimed;
        isLocked = userStake.lockEndTime > block.timestamp;
    }
    
    /**
     * @notice Get vault statistics
     */
    function getVaultStats() external view returns (
        uint256 totalStakedTokens,
        uint256 totalStakersCount,
        uint256 totalYield,
        uint256 distributionCount,
        uint256 avgAPY,
        uint256 currentMonthYield
    ) {
        totalStakedTokens = totalStaked;
        totalStakersCount = totalStakers;
        totalYield = totalYieldGenerated;
        distributionCount = distributions.length;
        avgAPY = averageAPY;
        currentMonthYield = monthlyYield[block.timestamp / 30 days];
    }
    
    /**
     * @notice Get reward pool information
     */
    function getRewardPoolInfo(address rewardToken) external view returns (
        uint256 accRewardPerShare,
        uint256 totalDistributed,
        uint256 lastDistributionTime,
        uint256 distributionCount
    ) {
        RewardPool storage pool = rewardPools[rewardToken];
        return (
            pool.accRewardPerShare,
            pool.totalDistributed,
            pool.lastDistributionTime,
            pool.distributionCount
        );
    }
    
    /**
     * @notice Get distribution history with pagination
     */
    function getDistributionHistory(
        uint256 offset,
        uint256 limit
    ) external view returns (RewardDistribution[] memory) {
        uint256 length = distributions.length;
        if (offset >= length) return new RewardDistribution[](0);
        
        uint256 end = offset + limit;
        if (end > length) end = length;
        
        RewardDistribution[] memory result = new RewardDistribution[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = distributions[i];
        }
        
        return result;
    }
    
    /**
     * @notice Calculate effective APY based on recent distributions
     */
    function calculateAPY() external view returns (uint256) {
        if (totalStaked == 0 || distributions.length == 0) return 0;
        
        // Calculate APY based on last 12 months of distributions
        uint256 yearlyYield = 0;
        uint256 cutoffTime = block.timestamp - 365 days;
        
        for (uint256 i = distributions.length; i > 0; i--) {
            if (distributions[i - 1].timestamp < cutoffTime) break;
            yearlyYield += distributions[i - 1].amount;
        }
        
        // Convert to percentage (basis points)
        return (yearlyYield * 10000) / totalStaked;
    }
    
    /**
     * @notice Get lock duration for stake type
     */
    function _getLockDuration(StakeType stakeType) internal pure returns (uint256) {
        if (stakeType == StakeType.LOCKED_30D) return 30 days;
        if (stakeType == StakeType.LOCKED_90D) return 90 days;
        if (stakeType == StakeType.LOCKED_365D) return 365 days;
        return 0;
    }
    
    // Admin functions
    
    /**
     * @notice Add supported reward token
     */
    function addRewardToken(
        address token,
        uint8 decimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!supportedRewardTokens[token], "Token already supported");
        
        supportedRewardTokens[token] = true;
        rewardTokenDecimals[token] = decimals;
        rewardTokensList.push(token);
        
        emit RewardTokenAdded(token, decimals);
    }
    
    /**
     * @notice Remove supported reward token
     */
    function removeRewardToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(supportedRewardTokens[token], "Token not supported");
        require(token != address(0), "Cannot remove ETH");
        
        supportedRewardTokens[token] = false;
        
        // Remove from array
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            if (rewardTokensList[i] == token) {
                rewardTokensList[i] = rewardTokensList[rewardTokensList.length - 1];
                rewardTokensList.pop();
                break;
            }
        }
        
        emit RewardTokenRemoved(token);
    }
    
    /**
     * @notice Update stake type multiplier
     */
    function updateStakeMultiplier(
        StakeType stakeType,
        uint256 multiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (multiplier < 5000 || multiplier > 50000) revert InvalidMultiplier(); // 0.5x to 5x
        
        stakeMultipliers[stakeType] = multiplier;
        emit StakeTypeUpdated(stakeType, multiplier);
    }
    
    /**
     * @notice Update vault configuration
     */
    function updateVaultConfig(
        uint256 newMinStake,
        uint256 newStakingFee,
        uint256 newEarlyUnstakeFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newStakingFee <= 1000, "Staking fee too high"); // Max 10%
        require(newEarlyUnstakeFee <= 2000, "Early unstake fee too high"); // Max 20%
        
        minStakeAmount = newMinStake;
        stakingFee = newStakingFee;
        earlyUnstakeFee = newEarlyUnstakeFee;
        
        emit VaultConfigUpdated(newMinStake, newStakingFee, newEarlyUnstakeFee);
    }
    
    /**
     * @notice Update admin address
     */
    function updateAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "Invalid admin");
        admin = newAdmin;
    }
    
    /**
     * @notice Update average APY (for display purposes)
     */
    function updateAverageAPY(uint256 newAPY) external onlyRole(YIELD_MANAGER_ROLE) {
        averageAPY = newAPY;
    }
    
    /**
     * @notice Pause the vault
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause the vault
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Emergency withdraw for admin
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(admin).transfer(amount);
        } else {
            IERC20(token).safeTransfer(admin, amount);
        }
    }
    
    /**
     * @notice Get supported reward tokens
     */
    function getSupportedRewardTokens() external view returns (address[] memory) {
        return rewardTokensList;
    }
    
    receive() external payable {
        // Allow direct ETH deposits for rewards
    }
}
