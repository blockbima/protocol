// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BlockBima MVP Capital Pool
/// @notice Gas-minimized pooled parametric insurance contract for climate risk with emergency pause
contract BlockBimaMVP {
    // --- Admin & Roles ---
    address public admin;

    // --- Token Settings ---
    IERC20 public immutable stablecoin;

    // --- Emergency Pause ---
    bool public paused;
    event Paused();
    event Unpaused();

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    // --- Capital Pool ---
    uint256 public capitalPool;

    // --- LP Accounting ---
    mapping(address => uint256) public lpBalances;
    uint256 public totalLPTokens;

    // --- Policy Data Structure ---
    struct Policy {
        address user;
        uint256 premium;
        uint256 maxPayout;
        uint256 startTime;
        uint256 endTime;
        uint256 payoutRatio;
        bool claimed;
        string region;
    }

    mapping(uint256 => Policy) public policies;
    uint256 public nextPolicyId;

    // --- Liquidity Buffer ---
    uint16 public reserveRatioBps = 3000; // 30%

    // --- Events ---
    event LPDeposited(address indexed lp, uint256 amount, uint256 lpTokensMinted);
    event PolicyCreated(uint256 indexed policyId, address indexed user, string region);
    event PolicySettled(uint256 indexed policyId, address indexed user, uint256 payout);
    event LPWithdraw(address indexed lp, uint256 lpTokensBurned, uint256 amountWithdrawn);

    // --- Constructor ---
    /// @param _stablecoin Address of ERC-20 stablecoin used for premiums and LP deposits
    /// @param _admin Multisig or admin address for MVP governance
    constructor(IERC20 _stablecoin, address _admin) {
        stablecoin = _stablecoin;
        admin = _admin;
        nextPolicyId = 1;
    }

    // --- Admin Functions ---
    /// @notice Pause all protocol operations
    function pause() external onlyAdmin {
        paused = true;
        emit Paused();
    }

    /// @notice Unpause protocol operations
    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused();
    }

    /// @notice Set a new reserve ratio (admin only)
    /// @param newRatioBps Basis points for reserve ratio (0-10000)
    function setReserveRatio(uint16 newRatioBps) external onlyAdmin {
        require(newRatioBps <= 10000, "Ratio too high");
        reserveRatioBps = newRatioBps;
    }

    // --- LP Deposit Function ---
    /// @notice Deposit stablecoin into the capital pool and mint LP tokens
    /// @param amount The amount of stablecoin to deposit
    function depositLP(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(stablecoin.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 minted;
        if (totalLPTokens == 0 || capitalPool == 0) {
            minted = amount;
        } else {
            minted = (amount * totalLPTokens) / capitalPool;
        }

        capitalPool += amount;
        lpBalances[msg.sender] += minted;
        totalLPTokens += minted;

        emit LPDeposited(msg.sender, amount, minted);
    }

    // --- Policy Creation ---
    /// @notice Purchase a policy by paying premium and storing policy data
    /// @param premium Amount of stablecoin as premium
    /// @param maxPayout Maximum payout in case of full trigger
    /// @param duration Policy duration in seconds
    /// @param region Region identifier string
    /// @return policyId The unique ID of the newly created policy
    function createPolicy(
        uint256 premium,
        uint256 maxPayout,
        uint256 duration,
        string calldata region
    ) external whenNotPaused returns (uint256 policyId) {
        require(premium > 0, "Premium must be > 0");
        require(maxPayout > 0, "Max payout must be > 0");
        require(duration > 0, "Duration must be > 0");
        require(stablecoin.transferFrom(msg.sender, address(this), premium), "Transfer failed");

        capitalPool += premium;
        policyId = nextPolicyId++;
        policies[policyId] = Policy({
            user: msg.sender,
            premium: premium,
            maxPayout: maxPayout,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            payoutRatio: 0,
            claimed: false,
            region: region
        });

        emit PolicyCreated(policyId, msg.sender, region);
    }

    // --- Policy Settlement ---
    /// @notice Batch settle policies by admin (oracle) providing payout ratio in bps (10000 = 100%)
    /// @param policyIds Array of policy IDs to settle
    /// @param payoutRatio Basis points payout ratio to apply (0-10000)
    function settlePolicies(
        uint256[] calldata policyIds,
        uint16 payoutRatio
    ) external onlyAdmin whenNotPaused {
        for (uint256 i = 0; i < policyIds.length; ) {
            uint256 id = policyIds[i];
            Policy storage p = policies[id];
            if (!p.claimed && block.timestamp >= p.endTime) {
                uint256 payout = (p.maxPayout * payoutRatio) / 10000;
                if (payout > capitalPool) payout = capitalPool;
                p.claimed = true;
                p.payoutRatio = payoutRatio;
                capitalPool -= payout;
                stablecoin.transfer(p.user, payout);
                emit PolicySettled(id, p.user, payout);
            }
            unchecked { i++; }
        }
    }

    // --- LP Withdrawal Function ---
    /// @notice Withdraw proportional share of available pool by burning LP tokens
    /// @param lpTokenAmount Amount of LP tokens to burn
    function withdrawLP(uint256 lpTokenAmount) external whenNotPaused {
        require(lpTokenAmount > 0, "Must withdraw > 0");
        uint256 userBalance = lpBalances[msg.sender];
        require(userBalance >= lpTokenAmount, "Insufficient LP balance");

        uint256 reserved = (capitalPool * reserveRatioBps) / 10000;
        uint256 available = capitalPool - reserved;
        uint256 withdrawAmount = (available * lpTokenAmount) / totalLPTokens;
        require(withdrawAmount > 0, "Withdraw amount zero or exceeds available liquidity");

        lpBalances[msg.sender] = userBalance - lpTokenAmount;
        totalLPTokens -= lpTokenAmount;
        capitalPool -= withdrawAmount;

        stablecoin.transfer(msg.sender, withdrawAmount);
        emit LPWithdraw(msg.sender, lpTokenAmount, withdrawAmount);
    }
}

