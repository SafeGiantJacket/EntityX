// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EntityMarketplace {
    struct Entity {
        string name;
        string category;
        uint256 unitPrice;
        string legalDocument;
        string entityImagesLink;
        uint256 totalUnits;
        uint256 unitsSold;
        uint256 unitsRented;
        address owner;
        uint256 rentPrice;
        uint256 rentExpiryTimestamp;
        mapping(address => uint256) unitHolders;
        address[] unitHoldersList;
        OwnershipRecord[] ownershipHistory;
        uint256 spamVotes;
        mapping(address => bool) spamVoters;
    }

    struct OwnershipRecord {
        address previousOwner;
        address newOwner;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    mapping(bytes32 => Entity) public entities;
    mapping(bytes32 => uint256) public unitPrices;
    bytes32[] public allEntities;

    event EntityCreated(bytes32 entityHash, string name, address owner);
    event EntityBought(bytes32 entityHash, address buyer);
    event EntityRented(bytes32 entityHash, address renter);
    event OwnershipTransferred(bytes32 entityHash, address previousOwner, address newOwner, uint256 timestamp, uint256 blockNumber);
    event EntityMarkedAsSpam(bytes32 entityHash, address voter);

    function createEntity(
        string memory _name,
        string memory _category,
        uint256 _unitPrice,
        string memory _legalDocument,
        string memory _entityImagesLink,
        uint256 _rentPrice,
        uint256 _rentExpiryTimestamp
    ) public {
        bytes32 entityHash = keccak256(abi.encodePacked(_name, _category, _unitPrice, _legalDocument, _entityImagesLink, msg.sender));
        Entity storage entity = entities[entityHash];
        entity.name = _name;
        entity.category = _category;
        entity.unitPrice = _unitPrice;
        entity.legalDocument = _legalDocument;
        entity.entityImagesLink = _entityImagesLink;
        entity.totalUnits = 100;
        entity.owner = msg.sender;
        entity.rentPrice = _rentPrice;
        entity.rentExpiryTimestamp = _rentExpiryTimestamp;
        unitPrices[entityHash] = _unitPrice;
        entity.unitHolders[msg.sender] = 100;
        entity.unitHoldersList.push(msg.sender);
        allEntities.push(entityHash);
        emit EntityCreated(entityHash, _name, msg.sender);
    }

    function viewAllEntities() public view returns (bytes32[] memory) {
        return allEntities;
    }

    function viewOwnershipRecord(bytes32 _entityHash, uint256 _recordIndex) public view returns (address, address, uint256, uint256) {
        require(_recordIndex < entities[_entityHash].ownershipHistory.length, "Invalid record index");
        OwnershipRecord storage record = entities[_entityHash].ownershipHistory[_recordIndex];
        return (
            record.previousOwner,
            record.newOwner,
            record.timestamp,
            record.blockNumber
        );
    }

    function viewEntitiesByOwner(address _owner) public view returns (bytes32[] memory) {
        bytes32[] memory ownerEntities = new bytes32[](allEntities.length);
        uint256 count = 0;
        for (uint256 i = 0; i < allEntities.length; i++) {
            if (entities[allEntities[i]].owner == _owner) {
                ownerEntities[count] = allEntities[i];
                count++;
            }
        }
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = ownerEntities[i];
        }
        return result;
    }

    function viewEntity(bytes32 _entityHash) public view returns (string memory, string memory, uint256, string memory, string memory, uint256, uint256, uint256, address, uint256, uint256, uint256) {
        Entity storage entity = entities[_entityHash];
        return (
            entity.name,
            entity.category,
            entity.unitPrice,
            entity.legalDocument,
            entity.entityImagesLink,
            entity.totalUnits,
            entity.unitsSold,
            entity.unitsRented,
            entity.owner,
            entity.rentPrice,
            entity.rentExpiryTimestamp,
            entity.spamVotes
        );
    }

    function sellEntity(bytes32 _entityHash, uint256 _sellingPrice) public {
        require(entities[_entityHash].owner == msg.sender, "You are not the owner of this entity");
        entities[_entityHash].unitPrice = _sellingPrice;
    }

    function rentEntity(bytes32 _entityHash, uint256 _rentPrice, uint256 _rentExpiryTimestamp) public {
        require(entities[_entityHash].owner == msg.sender, "You are not the owner of this entity");
        entities[_entityHash].rentPrice = _rentPrice;
        entities[_entityHash].rentExpiryTimestamp = _rentExpiryTimestamp;
    }

    function takeRent(bytes32 _entityHash) public payable {
        Entity storage entity = entities[_entityHash];
        require(entity.owner != address(0), "Entity does not exist");
        require(entity.owner != msg.sender, "You are already the owner of this entity");
        require(msg.value >= entity.rentPrice, "Insufficient rent fee");
        require(block.timestamp < entity.rentExpiryTimestamp, "Rent has expired");

        address previousOwner = entity.owner;
        entity.owner = msg.sender;
        entity.unitsRented = entity.totalUnits;
        entity.totalUnits = 0;

        distributeFunds(_entityHash, msg.value, previousOwner);

        emit EntityRented(_entityHash, msg.sender);
    }

    function buyUnits(bytes32 _entityHash, uint256 _unitsToBuy) public payable {
        Entity storage entity = entities[_entityHash];
        require(entity.totalUnits >= _unitsToBuy, "Not enough units available");
        require(msg.value >= entity.unitPrice * _unitsToBuy, "Incorrect amount sent");

        entity.unitHolders[msg.sender] += _unitsToBuy;
        entity.totalUnits -= _unitsToBuy;
        entity.unitsSold += _unitsToBuy;

        if (entity.unitHolders[msg.sender] == _unitsToBuy) {
            entity.unitHoldersList.push(msg.sender);
        }

        payable(entity.owner).transfer(msg.value);
    }

    function buyEntity(bytes32 _entityHash) public payable {
        Entity storage entity = entities[_entityHash];
        require(entity.owner != address(0), "Entity does not exist");
        require(entity.owner != msg.sender, "You already own this entity");
        require(msg.value >= entity.unitPrice, "Incorrect amount sent");

        address previousOwner = entity.owner;
        entity.ownershipHistory.push(OwnershipRecord({
            previousOwner: previousOwner,
            newOwner: msg.sender,
            timestamp: block.timestamp,
            blockNumber: block.number
        }));

        uint256 totalPayment = msg.value;
        distributeFunds(_entityHash, totalPayment, previousOwner);

        entity.owner = msg.sender;
        entity.totalUnits = 0;
        entity.unitsSold = 0;
        entity.unitsRented = 0;

        emit EntityBought(_entityHash, msg.sender);
        emit OwnershipTransferred(_entityHash, previousOwner, msg.sender, block.timestamp, block.number);
    }

    function voteSpam(bytes32 _entityHash) public {
        Entity storage entity = entities[_entityHash];
        require(entity.owner != address(0), "Entity does not exist");
        require(!entity.spamVoters[msg.sender], "You have already voted for this entity");

        entity.spamVoters[msg.sender] = true;
        entity.spamVotes += 1;

        emit EntityMarkedAsSpam(_entityHash, msg.sender);
    }

    function viewSpamVotes(bytes32 _entityHash) public view returns (uint256) {
        return entities[_entityHash].spamVotes;
    }

    function viewEntitiesMarkedAsSpam(uint256 _minVotes) public view returns (bytes32[] memory) {
        bytes32[] memory spamEntities = new bytes32[](allEntities.length);
        uint256 count = 0;
        for (uint256 i = 0; i < allEntities.length; i++) {
            if (entities[allEntities[i]].spamVotes >= _minVotes) {
                spamEntities[count] = allEntities[i];
                count++;
            }
        }
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = spamEntities[i];
        }
        return result;
    }

    function distributeFunds(bytes32 _entityHash, uint256 _totalPayment, address _previousOwner) internal {
        Entity storage entity = entities[_entityHash];
        uint256 totalUnits = entity.totalUnits;

        for (uint256 i = 0; i < entity.unitHoldersList.length; i++) {
            address holder = entity.unitHoldersList[i];
            uint256 unitsOwned = entity.unitHolders[holder];
            if (unitsOwned > 0) {
                uint256 payment = (unitsOwned * _totalPayment) / totalUnits;
                payable(holder).transfer(payment);
                entity.unitHolders[holder] = 0;
            }
        }
        payable(_previousOwner).transfer(address(this).balance); 
    }
}
