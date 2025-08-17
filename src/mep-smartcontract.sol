// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


//xxx this just initial, need more review
contract ProjectEscrow {

    // Struktur untuk menyimpan informasi tentang setiap milestone
    struct Milestone {
        uint256 amount;
        bool achieved;
        uint256 timestamp;
    }

    // Struktur untuk menyimpan status proyek
    struct Project {
        address worker;
        address client;
        uint256 totalAmount;
        uint256 fundsDeposited;
        bool isComplete;
    }

    // Mapping untuk menyimpan proyek berdasarkan projectId
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Milestone)) public projectMilestones;

    // Mapping untuk menyimpan saldo setiap proyek
    mapping(uint256 => uint256) public projectBalances;

    // Event untuk log pencairan dana
    event FundsDeposited(uint256 projectId, uint256 amount);
    event MilestoneAchieved(uint256 projectId, uint256 milestoneId);
    event FundsWithdrawn(uint256 projectId, uint256 amount);
    event RefundIssued(uint256 projectId, uint256 amount);

    // Fungsi untuk membuat proyek baru
    function createProject(uint256 projectId, address _client, address _worker, uint256 _totalAmount) public {
        require(projects[projectId].client == address(0), "Project already exists");
        projects[projectId] = Project({
            worker: _worker,
            client: _client,
            totalAmount: _totalAmount,
            fundsDeposited: 0,
            isComplete: false
        });
    }

    // Fungsi untuk menetapkan milestone untuk proyek
    function setMilestone(uint256 projectId, uint256 milestoneId, uint256 amount) public {
        require(msg.sender == projects[projectId].worker, "Only worker can set milestones");
        projectMilestones[projectId][milestoneId] = Milestone({
            amount: amount,
            achieved: false,
            timestamp: block.timestamp
        });
    }

    // Fungsi untuk deposit dana dari client ke smart contract
    function depositFunds(uint256 projectId, uint256 amount) public payable {
        require(msg.sender == projects[projectId].client, "Only client can deposit funds");
        require(msg.value == amount, "Deposit amount must match value sent");
        
        projects[projectId].fundsDeposited += amount;
        projectBalances[projectId] += amount;

        emit FundsDeposited(projectId, amount);
    }

    // Fungsi untuk mengajukan pencairan dana berdasarkan milestone
    function requestFunds(uint256 projectId, uint256 milestoneId) public {
        require(msg.sender == projects[projectId].worker, "Only worker can request funds");
        Milestone storage milestone = projectMilestones[projectId][milestoneId];
        require(milestone.amount > 0, "Milestone not set");
        require(!milestone.achieved, "Milestone already achieved");

        milestone.achieved = true;
        uint256 amountToWithdraw = milestone.amount;

        require(projectBalances[projectId] >= amountToWithdraw, "Insufficient funds in escrow");

        payable(projects[projectId].worker).transfer(amountToWithdraw);
        projectBalances[projectId] -= amountToWithdraw;

        emit MilestoneAchieved(projectId, milestoneId);
        emit FundsWithdrawn(projectId, amountToWithdraw);
    }

    // Fungsi untuk mengembalikan dana ke client jika milestone tidak tercapai dalam waktu yang ditentukan
    function issueRefund(uint256 projectId) public {
        Project storage project = projects[projectId];
        require(msg.sender == project.client, "Only client can request refund");
        require(!project.isComplete, "Project already completed");
        
        uint256 fundsToRefund = project.fundsDeposited;
        project.fundsDeposited = 0;
        projectBalances[projectId] = 0;
        
        payable(project.client).transfer(fundsToRefund);

        emit RefundIssued(projectId, fundsToRefund);
    }

    // Fungsi untuk menyelesaikan proyek dan mengonfirmasi bahwa semua dana telah diproses
    function completeProject(uint256 projectId) public {
        require(msg.sender == projects[projectId].worker, "Only worker can complete the project");
        projects[projectId].isComplete = true;
    }

    // Fungsi untuk mengambil status proyek
    function getProjectStatus(uint256 projectId) public view returns (bool, uint256, uint256) {
        Project storage project = projects[projectId];
        return (project.isComplete, project.fundsDeposited, project.totalAmount);
    }

    // Fungsi untuk mengambil status milestone
    function getMilestoneStatus(uint256 projectId, uint256 milestoneId) public view returns (bool, uint256, uint256) {
        Milestone storage milestone = projectMilestones[projectId][milestoneId];
        return (milestone.achieved, milestone.amount, milestone.timestamp);
    }
}
