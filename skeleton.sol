// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Importing ERC721URIStorage and Ownable contracts from OpenZeppelin for NFT functionality and access control
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Importing Counters utility from OpenZeppelin to use for token ID incrementing
import "@openzeppelin/contracts/utils/Counters.sol"; // Generation of token ID

// The Ticket contract inherits from ERC721URIStorage for NFT functionality and Ownable for access control
contract realestate is ERC721URIStorage, Ownable {
    //================================================ State Var =====================================================
    // Counters
    using Counters for Counters.Counter;        // Using the Counters library for the Counter type
    Counters.Counter private tokenIdCounter;    // Counter to keep track of token IDs Sample{1, 2, 3, 4 ...}
    uint256 contractIdCounter = 1;              // Counter for draft rental contract ID
    uint256 renterid = 1;                       // Counter for storing renter info

    // Owner related
    uint256 public listFeePercentage;           // Fee imposed on Landlord to Owner when they list property (eg. 1000000000000000000)
    uint256 public transactionFeePercentage;    // Fee imposed on renter to Owner when they paid rent       (eg. 1000000000000000000)
    uint256 transfeesRevenue;                   // Escrow revenue from transaction fees

    // Authorized Landlords & Renter
    mapping(address => bool) public authorizedLandlord; // Mapping of authorized landlord
    mapping(address => bool) public authorizedRenter;   // Mapping of authorized Renters

    // This contract will be solely used by one landlord and one property
    struct LandlordInfo{
        string landlordName;
        string landlordPhoneNumber;
        string landlordEmail;
        string landlordGender;
        uint256 landlordAge;
        bool landlordprovidedInfo;
    }
    LandlordInfo private landlord; // landlord register info


    // Property Information
    struct Property{
        uint256 tokenid;        // Determine by the token IDs Counter
        address owner;          // funciton callar: Landlord
        bool availiableForRent; // Avail For Rented --> true | Rented by someone already --> false
        uint256 rentprice;
        uint256 size;
        string location;
        string views;           // View of property: sea/hill/etc
        uint256 buildage;
    }
    Property public list_property; // Information of listed property
    
    struct Renter{
        uint256 renterId;
        string renterName;
        string renterPhoneNumber;
        string renterEmail;
        string renterGender;
        uint256 renterAge;
    }
    mapping (uint256 => Renter) private interestedRenters;
    // Once a renter object is created --> authorizedRenter given authorize to renter to state interest

    mapping(uint256 => Draft_PropertyRentalContract) private arr_draft_propertyRentalContract;
    struct Draft_PropertyRentalContract{
        uint256 draftContractid;        // The draft contract id of this instance
        uint256 propertyid;             // The interested property's token
        address interstedRenter;        // Store the interested renter wallet address
        address landlord;               // Store the landlord wallet address

        // Store bargaining information proposed by 2 parties:
        uint256 RentStartDate;
        uint256 RentEndDate;
        uint256 RentalExpenses;

        // Variable used during the bargaining process
        // Once any variable of the draft contract is modified, these 2 variables will be reset to false.
        // True means the party has reviewed the draft contract and agreed with the proposal.
        bool isRenterIn;                // Init as false by default
        bool isLandlordIn;              // Init as false by default

        // Variable used when there are successful agreement between 2 parties
        // True means both parties have agreed with the draft contract
        bool successSign;
    }

    struct Confirm_PropertyRentalContract{
        uint256 contractid;             // Same from Draft_PropertyRentalContract As Official Confirm Contract ID
        uint256 propertyId;
        address renter;                 // Store the renter wallet address
        address landlord;               // Store the landlord wallet address

        uint256 RentStartDate;          // Contract Start Date of renting property
        uint256 RentEndDate;            // Contract End Date of renting property
        uint256 RentalExpenses;         // Monthly payment

        uint256 totalRentExp;           // Total expense: (Rent period * rentExpenses)
        uint256 cumm_payment;           // Cummulative calculation of rent paid
        uint256 pricePool;              // Allow renter to pay rent, and landlord to withdraw
        bool forcedTerminate;           // false by default, and become true when focsed terminated
    }
    Confirm_PropertyRentalContract private confirmedContract; // Only one confirmed Contract will be in one Smart Contract

    //================================================ Init State ====================================================

    // Constructor to initialize the NFT contract with a name, symbol, and fee percentages (state variables)
    constructor(string memory name, string memory symbol, uint256 _listFeePercentage, uint256 _transactionFeePercentage)
        ERC721(name, symbol)  // Parent is ERC 721 Initialize the inherited ERC721 contract with the provided name and symbol
        Ownable(msg.sender) // Set the deployer of the contract as the initial owner
    {
        listFeePercentage = _listFeePercentage;                 // Set the creation fee percentage (ETH)
        transactionFeePercentage = _transactionFeePercentage;   // Set the rental fee percentage (ETH)

        emit contractINIT(msg.sender, listFeePercentage, transactionFeePercentage);
    }
    
    //================================================ modifiers =====================================================
    modifier onlyAuthorizedLandlord() {
        require(authorizedLandlord[msg.sender], "Not an authorized landlord.");
        _; // Continues execution of the function body
    }

    modifier onlyAuthorizedRenter() {
        require(authorizedRenter[msg.sender], "Not an authorized renter, please register.");
        _; // Continues execution of the function body
    }

    modifier onlyAuthorizedUser(){
        require(authorizedRenter[msg.sender] || authorizedLandlord[msg.sender], "Not an authorized user to view/modify contracts.");
        _; // Continues execution of the function body
    }

    //================================================ Functions =====================================================
    // Give permission to landlord to using our contract
    function provideLandlordAuth(address _landlord) external onlyOwner {
        authorizedLandlord[_landlord] = true;
    }

    // Landlord Function: The landlord provides their personal info to the smart contract
    function ll_landlordInfo(
        string memory _landlordName,
        string memory _landlordPhoneNumber,
        string memory _landlordEmail,
        string memory _landlordGender,
        uint256 _landlordAge
    ) external onlyAuthorizedLandlord
    {
        landlord.landlordName = _landlordName;
        landlord.landlordPhoneNumber = _landlordPhoneNumber;
        landlord.landlordEmail = _landlordEmail;
        landlord.landlordGender = _landlordGender;
        landlord.landlordAge = _landlordAge;
        landlord.landlordprovidedInfo = true; // Once landlord provided their personal info, they are allow to list property

        // Evenet emit
        emit landlordInfoReg(msg.sender, "Your Infomation is recorded");
    }

    // Landlord Function: Register the property
    function ll_listproperty(
        // Parameters of ll_listproperty
        // The URI for the token metadata
        string calldata tokenURI,
        uint256 _rentprice,
        uint256 _size,
        string memory _location,
        string memory _views,
        uint256 _age
    ) external payable onlyAuthorizedLandlord // The function is payable to accept Ether for the creation fee, and only callable by landlord
    {   
        // Can only list property after landlord provide their info
        require(landlord.landlordprovidedInfo, "Please provide your information before list property");

        // Get the current token ID and increment the counter for the next token
        uint256 currentID = tokenIdCounter.current(); // Set the ticket ID as the tokenIDCounter Value
        tokenIdCounter.increment();

        // Mint a new token to the sender and set its metadata URI
        _safeMint(msg.sender, currentID);   // Assigns the newly generated currentID as the token ID for the newly created token.
        _setTokenURI(currentID, tokenURI);  // Associates the token ID with the provided tokenURI.

        // Create a list_property object
        list_property = Property({
            tokenid: currentID,         // Token ID: first property start from 0!
            owner: msg.sender,          // Property Register Function Caller
            availiableForRent: true,    // true by default
            rentprice: _rentprice,
            size: _size,
            location: _location,
            views: _views,              // View: sea/hill/etc
            buildage:_age
        });

        uint256 listFee = listFeePercentage; // Calculate the creation fee based on the provided percentage

        // Ensure the correct creation fee is paid
        require(msg.value == listFee, "Incorrect list fee sent");

        // TRANSFER the creation fee to the contract owner
        payable(owner()).transfer(listFee); // assume this is a middle men fees paid to contract owner

        // Emit an event to log the creation of the new ticket
        emit propertyLog(currentID, "Property listed");
    }  
    // Internal function: Given draftContractId and user, return the type of user (either an interested renter or the landlord of that draft contract)
    function typeOfUser(uint _draftContractId, address user) internal view returns (string memory) {
        if (authorizedRenter[user]) {
            require(user == arr_draft_propertyRentalContract[_draftContractId].interstedRenter, "The sender is not authorized to modify this draft contract");
            return "Interested Renter";
        }
        else {
            return "Landlord";
        }
    }

    // Renter Function: register renter info
    function rt_registerInfo(
        string memory _renterName,
        string memory _renterPhoneNumber,
        string memory _renterEmail,
        string memory _renterGender,
        uint256 renterAge
    ) external
    {
        interestedRenters[renterid]=(Renter({
            renterId: renterid,
            renterName:_renterName,
            renterPhoneNumber:_renterPhoneNumber,
            renterEmail:_renterEmail,
            renterGender:_renterGender,
            renterAge:renterAge
        }));
        renterid = renterid +1;
        // Make msg.sender as authorize renter
        authorizedRenter[msg.sender]= true;

        // Emit the register result
        emit renterInfoReg(msg.sender, renterid, "Successfully Registered As Renter");
    }

    // Renter Function: State interest of property, with proposed rental budget in the draft contract
    function rt_interestproperty(
    // Parameters of ll_listproperty
    uint256 _rentstartdate,     // proposed the rent start date 
    uint256 _rentenddate,       // proposed the rent end date 
    uint256 _monthlybudget      // proposed the rent
    ) external onlyAuthorizedRenter
    {
        // Draft the rental contract
        arr_draft_propertyRentalContract[contractIdCounter]=(Draft_PropertyRentalContract({
            draftContractid: contractIdCounter,
            // Variables From Property Struct
            propertyid: list_property.tokenid,  // The interested property's token
            interstedRenter: msg.sender,        // Store the interested renter wallet address
            landlord: list_property.owner,      // Store the landlord wallet address

            // Store bargaining information proposed by 2 parties,
            // Both parties can adjust & update it upon review the draft rental contract
            RentStartDate: _rentstartdate,
            RentEndDate: _rentenddate,
            RentalExpenses: _monthlybudget,

            // Variable used during the bargaining process
            isRenterIn: false,                  // set as false when init, cuz renter may not know how landlord feel about the proposal
            isLandlordIn: false,                // set as false when init, cuz landlord has not review the draft rental contract yet

            // Variable used when there are successful agreement between 2 parties
            successSign: false                  // set as false when init
        }));

        contractIdCounter = contractIdCounter + 1;

        // Event emit on the interested to the property
        emit renterInterest(msg.sender, list_property.tokenid);
    }

    // Function: Review a draft_propertyRentalContract by its id
    function reviewDraftcontract(uint draftContractId) external onlyAuthorizedUser returns (Draft_PropertyRentalContract memory) {
        // Check if the draft contract ID is valid
        require(draftContractId < contractIdCounter, "Invalid draft contract ID");

        // Check if the sender is valid and get the type of user (either an interested renter or the landlord of that draft contract)
        string memory _typeOfUser = typeOfUser(draftContractId, msg.sender);

        // Emit an event to log the review of the draft contract
        emit DraftContractReviewed(draftContractId, msg.sender, _typeOfUser);

        // Return the draft contract from the mapping
        return arr_draft_propertyRentalContract[draftContractId];        
    }

    // Function: Modify a draft contract by either the landlord or an intereted renter
    // Things can be modified: RentStartDate, RentEndDate, and RentalExpenses
    function modifyDraftcontract(
        uint draftContractId, 
        uint256 _rentStartDate, 
        uint256 _rentEndDate, 
        uint256 _rentalExpenses
        ) external onlyAuthorizedUser {
        // Check if the draft contract ID is valid
        require(draftContractId < contractIdCounter, "Invalid draft contract ID");

        // Check if the property status is available
        require(list_property.availiableForRent == true, "The property is rented by someone already");

        // Check if the sender is valid and get the type of user (either an interested renter or the landlord of that draft contract)
        string memory _typeOfUser = typeOfUser(draftContractId, msg.sender);

        // Update isLandlordIn and isRenterIn to false if needed
        if (arr_draft_propertyRentalContract[draftContractId].isLandlordIn == true)
            arr_draft_propertyRentalContract[draftContractId].isLandlordIn = false;
        if (arr_draft_propertyRentalContract[draftContractId].isRenterIn == true)
            arr_draft_propertyRentalContract[draftContractId].isRenterIn = false;

        string memory _modifiedValues = ""; // A string to store the modified values

        // Moditfy draft contract
        if (_rentStartDate != arr_draft_propertyRentalContract[draftContractId].RentStartDate || _rentStartDate != 0) {
            arr_draft_propertyRentalContract[draftContractId].RentStartDate = _rentStartDate;
            _modifiedValues = string.concat(_modifiedValues, "Rent Start Date. ");
        }
        if (_rentEndDate != arr_draft_propertyRentalContract[draftContractId].RentEndDate || _rentEndDate != 0) {
            arr_draft_propertyRentalContract[draftContractId].RentEndDate = _rentEndDate;
            _modifiedValues = string.concat(_modifiedValues, "Rent End Date. ");
        }
        if (_rentalExpenses != arr_draft_propertyRentalContract[draftContractId].RentalExpenses || _rentalExpenses != 0) {
            arr_draft_propertyRentalContract[draftContractId].RentalExpenses = _rentalExpenses;
            _modifiedValues = string.concat(_modifiedValues, "Rental Expenses. ");
        }
        
        // Emit an event for the modification of the draft contract
        emit DraftContractModified(draftContractId, msg.sender, _typeOfUser, _modifiedValues);
    }

    // Function: user accepts the draft contract. If both parties accept the draft contract, it will be converted to a confirmed contract
    function acceptDraftcontract(uint draftContractId) external onlyAuthorizedUser {
        // Check if the property is available for rent
        require(list_property.availiableForRent == true, "The property is rented by someone already");
        
        // Check if the draft contract ID is valid
        require(draftContractId < contractIdCounter, "Invalid draft contract ID");

        // Check if the sender is valid and get the type of user (either an interested renter or the landlord of that draft contract)
        string memory _typeOfUser = typeOfUser(draftContractId, msg.sender);

        // Update draftContract - isLandlordIn or isRenterIn
        if (keccak256(abi.encodePacked(_typeOfUser)) == keccak256(abi.encodePacked("Landlord"))) {
            arr_draft_propertyRentalContract[draftContractId].isLandlordIn = true;
        }
        else {
            arr_draft_propertyRentalContract[draftContractId].isRenterIn = true;
        }

        // Emit an event for the acceptance of the draft contract
        emit DraftContractAccepted(draftContractId, msg.sender, _typeOfUser);

        // If both parties have accepted the draft contract -> convert it to a confirmed contract
        if (arr_draft_propertyRentalContract[draftContractId].isLandlordIn && arr_draft_propertyRentalContract[draftContractId].isRenterIn) {
            // Call the confirmContract function to check accepted the draft contract or not and convert it to a confirmed contract
            confirmContract(arr_draft_propertyRentalContract[draftContractId]);
        }
    }
    
    // Internal function: Confirm the contract after both parties accepted the draft contract
    function confirmContract(Draft_PropertyRentalContract memory draftContract) internal {
        // Set the successSign to true
        draftContract.successSign = true;

        // Copy the member variables from the draft contract struct
        confirmedContract.contractid = draftContract.draftContractid;
        confirmedContract.propertyId = list_property.tokenid;
        confirmedContract.renter = draftContract.interstedRenter;
        confirmedContract.landlord = draftContract.landlord;
        confirmedContract.RentStartDate = draftContract.RentStartDate;
        confirmedContract.RentEndDate = draftContract.RentEndDate;
        confirmedContract.RentalExpenses = draftContract.RentalExpenses;

        // Set up the price pool
        // Convert epoch timestamps to years, months, and days
        (uint256 start_year, uint256 start_month, uint256 start_day) = _timestampToDate(draftContract.RentStartDate);
        (uint256 end_year, uint256 end_month, uint256 end_day) = _timestampToDate(draftContract.RentEndDate);

        // Calculate the difference in months
        uint256 monthsDiff;

        if (end_month >= start_month) {
            monthsDiff = (end_year - start_year) * 12 + (end_month - start_month);
        } else {
            monthsDiff = (end_year - start_year - 1) * 12 + (12 - start_month + end_month);
        }

        confirmedContract.totalRentExp = monthsDiff * draftContract.RentalExpenses; // Rent period * rentExpenses
        confirmedContract.cumm_payment = 0;                                         // Renter has not started paying rent
        confirmedContract.pricePool = 0;                                            // Renter has not started paying rent
        confirmedContract.forcedTerminate = false;                                  // False by default, and becomes true when the contract comes to the end date OR other circumstances

        list_property.availiableForRent = false;

        // Emit an event for the confirmation of sign for the contract
        emit ContractConfirmed(confirmedContract.contractid, confirmedContract.landlord, confirmedContract.renter);
    }

    // Assist on creation of confirmed contract: Function to convert timestamp to year, month, and day
    function _timestampToDate(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
        // Assuming a year has 365 days for simplicity
        uint256 secondsInDay = 86400;
        uint256 secondsInYear = 365 * secondsInDay;
        
        // Calculate year
        year = timestamp / secondsInYear;
        
        // Calculate remaining seconds after removing full years
        uint256 remainingSeconds = timestamp % secondsInYear;
        
        // Calculate month
        month = remainingSeconds / (30 * secondsInDay); // Assuming a month has 30 days for simplicity
        
        // Calculate remaining seconds after removing full months
        remainingSeconds %= 30 * secondsInDay;
        
        // Calculate day
        day = remainingSeconds / secondsInDay;
    }
    

    // Renter Function: make deposit - payable
    function rt_payRent() external payable onlyAuthorizedRenter {
        // Check if msg.value + current cumm_payment <= totalRentExp???
        // Set up a minimum deposit amount for renter everytime they make deposit
        uint256 minimalDepositAmt = confirmedContract.RentalExpenses;

        // Check if the message sender is the signed contract renter
        require(msg.sender == confirmedContract.renter, "You are not the signed contract renter");

        // Check if the contract already reached its end date
        require(block.timestamp < confirmedContract.RentEndDate, "The contract is reached to the end date");

        // Check if the contract is being terminated or not
        require(confirmedContract.forcedTerminate == false, "The contract was force terminated");

        // Check if the renter already paid all the rental expenses over the rental period
        require(confirmedContract.cumm_payment < confirmedContract.totalRentExp, "You already paid all the rental expenses");

        // Check if the current deposit amount larger or equals to the minimum deposit amount
        uint256 totalMinimalFeesReq = minimalDepositAmt + transactionFeePercentage;
        
        // Check the deposit amount is valid and meet the minimal requirement
        require(msg.value >= totalMinimalFeesReq, "Your deposit is lower than the minimal amount requirement: transaction fees + monthly rental expenses");

        // Calculate the amount of deposit that is contribute to the accumulative rental expenses pool
        uint256 deposit_to_pricePool = msg.value - transactionFeePercentage;

        // Increase the price pool and the accumulative payment by the deposit payments
        confirmedContract.cumm_payment += deposit_to_pricePool;
        confirmedContract.pricePool += deposit_to_pricePool;

        // Avoid access payment being put into the price pool
        if (confirmedContract.cumm_payment>confirmedContract.totalRentExp){
            uint256 deductFromPricePool = confirmedContract.cumm_payment - confirmedContract.totalRentExp;
            confirmedContract.pricePool = confirmedContract.pricePool - deductFromPricePool;
        }
        
        // Record the transaction fees Revenue
        transfeesRevenue = transfeesRevenue + transactionFeePercentage;

        // Emit the successful deposit payment
        emit RenterPaidRent(confirmedContract.contractid, minimalDepositAmt, deposit_to_pricePool, confirmedContract.cumm_payment, "Deposit Received");
    }

    // Renter Function: let renter collect the excess payment to the contract
    function rt_collectExcessPayment() external onlyAuthorizedRenter{
        // Check if msg.sender is the renter of the signed contract
        require(confirmedContract.renter == msg.sender, "You are not authorized to use this function");

        // Check if excessPayment exist
        uint256 excessPayment = confirmedContract.cumm_payment - confirmedContract.totalRentExp;
        require(excessPayment > 0, "You do not have any excess payment");

        // Reduce the cummulative payment amount by the excess payment
        confirmedContract.cumm_payment = confirmedContract.cumm_payment - excessPayment;

        // Pay the request collection amount to the contract owner
        payable(msg.sender).transfer(excessPayment);
    }

    // Landlord Function: rent collection
    function ll_collectrent(uint256 _collectAmt) external payable onlyAuthorizedLandlord {

        // Check if the price pool has enough currency for landlord to collect
        require(confirmedContract.pricePool > _collectAmt, "Your requested amount is larger than deposit price pool");

        // Decrease the price pool by the requested amount
        confirmedContract.pricePool -= _collectAmt;

        // Transfer the requested ETH to the landlord
        payable(msg.sender).transfer(_collectAmt);

        // Event emit about the rentCollection
        emit LandlordCollectRent(confirmedContract.contractid, _collectAmt, confirmedContract.pricePool, "Rent Collected from landlord");  
    }

    // Owner Function: allow owner to collect the transaction fees revenue
    function owner_TransRevenueCollect(uint256 _reqCollection) external onlyOwner{
        // Check if the requested collection amount is lower than or equal to the revenue amount
        require(_reqCollection<=transfeesRevenue, "Insufficent transaction revenue");
        
        // Update revenue amount 
        transfeesRevenue = transfeesRevenue - _reqCollection;

        // Pay the request collection amount to the contract owner
        payable(owner()).transfer(_reqCollection);
    }
    
    // Force terminate Function
    function forceTerminateContract(string memory _reason) external onlyAuthorizedUser {
        // Condition
        require(confirmedContract.forcedTerminate == false, "Contract Already Terminated");
        // Change state
        confirmedContract.forcedTerminate = true;   // current contract
        list_property.availiableForRent = true;     // Property Status
        // Emit Event
        emit ForceTerminated(confirmedContract.contractid, msg.sender, _reason);
    }

    // Events 
    
    // Event log: when the contract being deployed
    event contractINIT(address contract_owner, uint256 listfee, uint256 rentfee);

    // Event log: when the landlord successfully registered their personal info
    event landlordInfoReg(address landlord, string regDetails);

    // Event log: list/withdraw property from landlord
    event propertyLog(uint256 indexed property_id, string actionDetails);

    // Event log: when the landlord successfully registered their personal info
    event renterInfoReg(address renter, uint256 indexed renter_id, string regDetails);

    // Event log: when the landlord successfully registered their personal info
    event renterInterest(address renter, uint256 indexed property_id);

    // Event emit: upstage draft contract to confirmed contract
    event ContractConfirmed(uint256 confirmedContractid, address landlord, address renter);

    // event of Force termination
    event ForceTerminated(uint256 indexed contractid, address terminator, string reason);

    // Event log: when the landlord or a potentail renter reviewed a draft contract
    event DraftContractReviewed(uint256 indexed contract_id, address user, string typeOfUser);

    // Event log: any modification made on a draft contract
    event DraftContractModified(uint256 indexed contract_id, address user, string typeOfUser, string modifiedValues);

    // Event log: when the landlord or a potential renter accepted a draft contract
    event DraftContractAccepted(uint256 indexed contract_id, address user, string typeOfUser);

    // Event log: any deposit event from renter are logged and inform them about their accumulative rental fees paid
    event RenterPaidRent(uint256 indexed contractid, uint256 renterFees, uint256 actualDepositAmount, uint256 accumulativeRentPayment, string depositResult);

    // Event log: any deposit event from renter are logged and inform them about their accumulative rental fees paid
    event LandlordCollectRent(uint256 indexed contractid, uint256 collectAmount, uint256 remainPricePool, string collectResult);
    
    // Event log: return excess payment to renter
    event ExcessPayment(address renter, uint256 returnAmt);

    // --- View Functions ---
    // Function: Let interested renter to check on Landlord Info
    function rt_getLandlordInfo() external view onlyAuthorizedRenter returns (LandlordInfo memory) {
        return landlord;
    }

    // Function: To view a property
    function viewProperty() external view onlyAuthorizedUser returns (Property memory) {
        return list_property;
    }

    // Function: To view a confirm contract
    function viewConfirmedContract() external view onlyAuthorizedUser returns (Confirm_PropertyRentalContract memory) {
        require(msg.sender ==confirmedContract.landlord || msg.sender ==confirmedContract.renter, "You are not the contract stakeholders");
        return confirmedContract;
    }
    
    // Function: To view a draft contract
    function viewDraftContract(uint256 _draftID) external view onlyAuthorizedUser returns (Draft_PropertyRentalContract memory) {
        require(msg.sender ==arr_draft_propertyRentalContract[_draftID].landlord || msg.sender ==arr_draft_propertyRentalContract[_draftID].interstedRenter, "You are not the contract stakeholders");
        return arr_draft_propertyRentalContract[_draftID];
    }
}