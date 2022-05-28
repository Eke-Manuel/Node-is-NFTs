// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "base64-sol/base64.sol";

// File: contracts/DorisNFT.sol

contract DorisNFT is ERC721URIStorage, Ownable, ChainlinkClient, KeeperCompatibleInterface {
    using Strings for uint256;
    using Counters for Counters.Counter;
    using Chainlink for Chainlink.Request;

    Counters.Counter private tokenIds;

    uint256 public cost;
    uint256 public maxSupply;
    address public factory;
    address public platform;
    address public doris;     //contract owner
    address public artist;
    uint8 public artistfees;
    uint8 public dorisfees;
    uint256 public fee;
    bytes32 public jobId;    //JobId for the GET request
    bool public paused = true;

    bytes32[] requestIds;
    weatherNFT[] public weather_nfts;
    string[5] precipitationTypes = ["No precipitation", "Rain", "Snow", "Ice", "Mixed"];

    address private keeperRegistryAddress;
    uint256 private waitPeriodSeconds;

     error OnlyKeeperRegistry();

    /* ========== TOKEN STRUCTURE ========== */

    struct weatherNFT {
        string location;
        string precipitationType;
        uint256 timestamp;
        uint24 precipitationPast24Hours;
        uint24 pressure;
        uint16 temperature;
        uint16 windDirectionDegrees;
        uint16 windSpeed;
        uint8 relativeHumidity;
        uint8 uvIndex;
    }

    /* STUCTURE TO STORE TOKEN DETAILS TO BE USED FOR TOKEN UPDATE */
    struct Target {
        string location;
        string lat;
        string lon;
        string[4] imageURIs;
        uint56 lastUpdateTimestamp;
        bool isActive;
    }
    
    /* ========== CONSUMER STATE VARIABLES ========== */

    struct RequestParams {
        uint256 locationKey;
        string endpoint;
        string lat;
        string lon;
        string units;
    }

    struct LocationResult {
        uint256 locationKey;
        string name;
        bytes2 countryCode;
    }
   
    struct CurrentConditionsResult {
        uint256 timestamp;
        uint24 precipitationPast12Hours;
        uint24 precipitationPast24Hours;
        uint24 precipitationPastHour;
        uint24 pressure;
        uint16 temperature;
        uint16 windDirectionDegrees;
        uint16 windSpeed;
        uint8 precipitationType;
        uint8 relativeHumidity;
        uint8 uvIndex;
        uint8 weatherIcon;
    }

     /* ========== MAPS ========== */

    mapping(bytes32 => CurrentConditionsResult) public requestIdCurrentConditionsResult;
    mapping(bytes32 => LocationResult) public requestIdLocationResult;
    mapping(bytes32 => RequestParams) public requestIdRequestParams;
    mapping(uint256 => weatherNFT) public tokenIdToToken;
    mapping(uint256 => Target) public tokenIdToTarget;


    /* ========== CONSTRUCTOR ========== */

    /**
    * @param _link the LINK token address.
    * @param _oracle the Operator.sol contract address.
    * @param _keeperRegistryAddress The address of the keeper registry contract
    * @param _waitPeriodSeconds The minimum wait period for tokens before update
    */
    constructor(
        address _platform,
        address _doris,
        address _link, 
        address _oracle,
        address _keeperRegistryAddress,
        uint256 _waitPeriodSeconds,
        string memory _name, 
        string memory _symbol
        ) ERC721(_name,_symbol) payable {
        
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        setKeeperRegistryAddress(_keeperRegistryAddress);
        setWaitPeriodSeconds(_waitPeriodSeconds);
        
        factory = msg.sender;
        doris = _doris;
        platform = _platform;
    }

    receive() external payable {
        revert("Don't send funds here");
    }

    modifier unpaused {
        require(!paused, "NFT paused");
        _;
    }
    modifier onlyPlatform {
        require(msg.sender == platform || msg.sender == doris, "Not platform");
        _;
    }
    modifier onlyDoris {
        require(msg.sender==doris, "Unauthorised");
        _;
    }
    modifier onlyKeeperRegistry() {
        if (msg.sender != keeperRegistryAddress) {
        revert OnlyKeeperRegistry();
        }
        _;
    }







    /**    ========== API consumer ========== 
     @dev
     * precipitationType (uint8)
    * --------------------------
    * Value    Type
    * --------------------------
    * 0        No precipitation
    * 1        Rain
    * 2        Snow
    * 3        Ice
    * 4        Mixed

    * Current weather conditions units per system
    * ---------------------------------------------------
    * Condition                    metric      imperial
    * ---------------------------------------------------
    * pressure                     mb          inHg
    * temperature                  C           F
    * windSpeed                    km/h        mi/h
    */

    
    /**
     * @notice Returns the current weather conditions of a location for the given coordinates.
     * @dev Uses @chainlink/contracts 0.4.0.
     * @param _jobId the jobID.
     * @param _fee the LINK amount in Juels (i.e. 10^18 aka 1 LINK).
     * @param _lat the latitude (WGS84 standard, from -90 to 90).
     * @param _lon the longitude (WGS84 standard, from -180 to 180).
     * @param _units the measurement system ("metric" or "imperial").
    */

    

    function requestLocationCurrentConditions(
        bytes32 _jobId,
        uint256 _fee,
        string memory _lat,
        string memory _lon,
        string memory _units
    ) public {
            LinkTokenInterface linkToken = LinkTokenInterface(chainlinkTokenAddress());
        require( linkToken.balanceOf(address(this)) >= _fee,
         "Not enough LINK- fund contract!"
         );
        
        Chainlink.Request memory request = buildChainlinkRequest(
            _jobId,
            address(this),
            this.fulfillLocationCurrentConditions.selector
        );

        request.add("lat", _lat);
        request.add("lon", _lon);
        request.add("units", _units);

        bytes32 requestId = sendChainlinkRequest(request, _fee);

        storeRequestParams(requestId, 0, "location-current-conditions", _lat, _lon, _units);
    }


    /*======FULFILMENT FUNCTIION====== **/
    /**
     * @notice Consumes the data returned by the node job on a particular request.
     * @dev Only when `_locationFound` is true, both `_locationFound` and `_currentConditionsResult` will contain
     * meaningful data (as bytes). 
     * @param _requestId the request ID for fulfillment.
     * @param _locationFound true if a location was found for the given coordinates, otherwise false.
     * @param _locationResult the location information (encoded as LocationResult).
     * @param _currentConditionsResult the current weather conditions (encoded as CurrentConditionsResult).
    */


    function fulfillLocationCurrentConditions(
        bytes32 _requestId,
        bool _locationFound,
        bytes memory _locationResult,
        bytes memory _currentConditionsResult
    ) public recordChainlinkFulfillment(_requestId) {
        if (_locationFound) {
            storeLocationResult(_requestId, _locationResult);
            storeCurrentConditionsResult(_requestId, _currentConditionsResult);
        }
    }


    function createToken(
        string memory _location,
        string calldata _lat,
        string calldata _lon,
        string[4] memory _imageURIs
        ) public onlyDoris {

        require(tokenIds.current() < maxSupply, "Max supply reached");

        requestLocationCurrentConditions(jobId,fee,_lat,_lon,"metric");
        _createToken(_location);

        uint256 tokenId = tokenIds.current();
        _safeMint(msg.sender, tokenId);

        tokenIdToTarget[tokenId] = Target({
        location: _location,
        lat: _lat,
        lon: _lon,
        imageURIs: _imageURIs,
        lastUpdateTimestamp: 0,
        isActive: true
      });

        tokenIdToToken[tokenId] = weather_nfts[tokenId];
        tokenIds.increment();
    }

    function updateToken(uint256[] memory outdatedTokens) public unpaused {
        uint256 m_waitPeriodSeconds = waitPeriodSeconds;
        Target memory target;
        for(uint256 idx = 0; idx < outdatedTokens.length; idx++) {
            target = tokenIdToTarget[outdatedTokens[idx]];
            string memory lat = target.lat;
            string memory lon = target.lon;
            if(target.isActive && target.lastUpdateTimestamp + m_waitPeriodSeconds <= block.timestamp){
                requestLocationCurrentConditions(jobId, fee, lat, lon, "metric");
                _updateToken(target.location, outdatedTokens[idx]);
                target.lastUpdateTimestamp = uint56(block.timestamp);

            }
        }

    }


    function formatTokenURI(
        weatherNFT memory _newToken,
        uint256 _tokenId 
    ) internal returns (string memory) {
        return string(abi.encodePacked(
            "data:application/json;base64,", _base64(_newToken, _tokenId))
        );    
    }

    function getOutdatedTokenIds() public view returns(uint[] memory) {
        uint256[] memory needsUpdate;
        uint256 m_waitPeriodSeconds = waitPeriodSeconds;
        Target memory target;
        for(uint256 idx = 0; idx < weather_nfts.length; idx++){
            target = tokenIdToTarget[idx];
            if(target.isActive && target.lastUpdateTimestamp + m_waitPeriodSeconds <= block.timestamp){
                needsUpdate[idx] = idx;
            }
        }
        return needsUpdate;
    }

    /**
   * @notice Get list of tokenIds for tokens that are outdated and return keeper-compatible payload
   * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds
   */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        unpaused
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256[] memory needsUpdate = getOutdatedTokenIds();
        upkeepNeeded = needsUpdate.length > 0;
        performData = abi.encode(needsUpdate);
        return (upkeepNeeded, performData);
    }

    /**
   * @notice Called by keeper to update metadata of outdated tokens
   * @param performData The abi encoded list of token Ids to update
   */

  function performUpkeep(bytes calldata performData) external override          onlyKeeperRegistry unpaused {
    uint256[] memory needsUpdate = abi.decode(performData, (uint256[]));
    updateToken(needsUpdate);
  }





    /*======PRIVATE FUNCTIONS======**/
    function storeRequestParams(
        bytes32 _requestId,
        uint256 _locationKey,
        string memory _endpoint,
        string memory _lat,
        string memory _lon,
        string memory _units
    ) private {
        RequestParams memory requestParams;
        requestParams.locationKey = _locationKey;
        requestParams.endpoint = _endpoint;
        requestParams.lat = _lat;
        requestParams.lon = _lon;
        requestParams.units = _units;
        requestIdRequestParams[_requestId] = requestParams;
    }

    function storeLocationResult(bytes32 _requestId, bytes memory _locationResult) private {
        LocationResult memory result = abi.decode(_locationResult, (LocationResult));
        requestIdLocationResult[_requestId] = result;
    }

    function storeCurrentConditionsResult(bytes32 _requestId, bytes memory _currentConditionsResult) private {
        CurrentConditionsResult memory result = abi.decode(_currentConditionsResult, (CurrentConditionsResult));
        requestIdCurrentConditionsResult[_requestId] = result;
        requestIds.push(_requestId);
    }

    function _createToken(string memory _location) private {
        weatherNFT memory newToken;
       
        newToken.location = _location;

        newToken.timestamp = requestIdCurrentConditionsResult[requestIds[requestIds.length]].timestamp;

        newToken.precipitationPast24Hours = requestIdCurrentConditionsResult[requestIds[requestIds.length]].precipitationPast24Hours;

        newToken.pressure = requestIdCurrentConditionsResult[requestIds[requestIds.length]].pressure;

        newToken.temperature = requestIdCurrentConditionsResult[requestIds[requestIds.length]].temperature;

        newToken.windDirectionDegrees = requestIdCurrentConditionsResult[requestIds[requestIds.length]].windDirectionDegrees;

        newToken.windSpeed = requestIdCurrentConditionsResult[requestIds[requestIds.length]].windSpeed;

        newToken.precipitationType = precipitationTypes[requestIdCurrentConditionsResult[requestIds[requestIds.length]].precipitationType];

        newToken.relativeHumidity = requestIdCurrentConditionsResult[requestIds[requestIds.length]].relativeHumidity;

        newToken.uvIndex = requestIdCurrentConditionsResult[requestIds[requestIds.length]].uvIndex;

        _setTokenURI(tokenIds.current(), formatTokenURI(newToken, tokenIds.current()));
        weather_nfts.push(newToken);
    }

    function _updateToken(string memory _location, uint256 _tokenId) private {
        weatherNFT memory newToken;
       
        newToken.location = _location;

        newToken.timestamp = requestIdCurrentConditionsResult[requestIds[requestIds.length]].timestamp;

        newToken.precipitationPast24Hours = requestIdCurrentConditionsResult[requestIds[requestIds.length]].precipitationPast24Hours;

        newToken.pressure = requestIdCurrentConditionsResult[requestIds[requestIds.length]].pressure;

        newToken.temperature = requestIdCurrentConditionsResult[requestIds[requestIds.length]].temperature;

        newToken.windDirectionDegrees = requestIdCurrentConditionsResult[requestIds[requestIds.length]].windDirectionDegrees;

        newToken.windSpeed = requestIdCurrentConditionsResult[requestIds[requestIds.length]].windSpeed;

        newToken.precipitationType = precipitationTypes[requestIdCurrentConditionsResult[requestIds[requestIds.length]].precipitationType];

        newToken.relativeHumidity = requestIdCurrentConditionsResult[requestIds[requestIds.length]].relativeHumidity;

        newToken.uvIndex = requestIdCurrentConditionsResult[requestIds[requestIds.length]].uvIndex;

        _setTokenURI(tokenIds.current(), formatTokenURI(newToken, _tokenId));
    }


    /**@dev Consumes a token and returns a base64 encoded string of the token's metadata */

    function _base64(weatherNFT memory _newToken, uint256 _tokenId) 
        private view returns(string memory) {
        return(Base64.encode(bytes(
                        abi.encodePacked(
                            '{"name": "Weather NFT"',
                            '"description": "A collection of artworks of landscapes/places around the world that respond to physical conditions at the location"' ,
                            '"image":',tokenIdToTarget[_tokenId].imageURIs[requestIdCurrentConditionsResult[requestIds[requestIds.length]].precipitationType],
                            '"attributes": [',
                                '{',
                                    '"condition_type": "Location"',
                                    '"value":', _newToken.location,
                                '}',
                                '{',
                                    '"condition_type": "Precipitation Type"',
                                    '"value":', _newToken.precipitationType,
                                '}',
                                '{',
                                    '"condition_type": "Timestamp"',
                                    '"value":', _newToken.timestamp,
                                '}',
                                '{',
                                    '"condition_type": "Precipitation past 24 hours"',
                                    '"value":', _newToken.precipitationPast24Hours,
                                '}',
                                '{',
                                    '"condition_type": "Pressure"',
                                    '"value":', _newToken.pressure,
                                '}',
                                '{',
                                    '"condition_type": "Temprature"',
                                    '"value":', _newToken.temperature,
                                '}',
                                '{',
                                    '"condition_type": "Wind direction in degrees"',
                                    '"value":', _newToken.windDirectionDegrees,
                                '}',
                                '{',
                                    '"condition_type": "Wind speed"',
                                    '"value":', _newToken.windSpeed,
                                '}',
                                '{',
                                    '"condition_type": "Relative humidity"',
                                    '"value":', _newToken.relativeHumidity,
                                '}',
                                '{',
                                    '"condition_type": "uvIndex"',
                                    '"value":', _newToken.uvIndex,
                                '}',
                            ']'
                        '}'
                            
                        )
                    )));
    }





    /* ========== SETTERS ========== */

    function setKeeperRegistryAddress(address _keeperRegistryAddress) public onlyPlatform {
        require(_keeperRegistryAddress != address(0));
        keeperRegistryAddress = _keeperRegistryAddress;
    }

    function setWaitPeriodSeconds(uint256 _period) public onlyDoris {
        waitPeriodSeconds = _period;
    }

    function setOracle(address _oracle) external onlyDoris {
        setChainlinkOracle(_oracle);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyPlatform {
        maxSupply = _maxSupply == 0 ? 2**256-1 : _maxSupply;
    }

    function setJobidAndFee(bytes32 _jobId, uint256 _fee) external onlyPlatform {
        jobId = _jobId;
        fee = _fee;
    }

    function setTokenPrice(uint256 _cost) external onlyDoris {
        cost = _cost;
    }

    function setArtist(address _artist) external onlyPlatform {
        artist = _artist;
    }

    function setFees(uint8 _dorisfees, uint8 _artistfees) external onlyDoris {
        require((_artistfees + _dorisfees)<=100, "Fees > 100%");
        dorisfees = _dorisfees;
        artistfees = _artistfees;
    }

    function pauseToken(uint256 _tokenId) external onlyOwner {
        tokenIdToTarget[_tokenId].isActive = false;
    }

    function unpauseToken(uint256 _tokenId) external onlyOwner {
        tokenIdToTarget[_tokenId].isActive = true;
    }


    /* ========= GETTERS ========= */
    function getOracleAddress() external view returns (address) {
        return chainlinkOracleAddress();
    }

    function withdrawLink() public onlyDoris {
        LinkTokenInterface linkToken = LinkTokenInterface(chainlinkTokenAddress());
        require(linkToken.transfer(msg.sender, linkToken.balanceOf(address(this))), "Unable to withdraw funds");
    }

    function togglePause() public onlyPlatform {
        paused = !paused;
    }

    function totalSupply() public view returns (uint256) {
        return tokenIds.current();
    }



    /* ========= OTHER FUNCTIONS ========= */

    /**@notice Transfers token from contract creator to _to 
     */
    function mint(address _to, uint256 _tokenId) external payable unpaused {
        require(msg.value >= cost, "Value is less than token cost");
        require(_tokenId <= tokenIds.current(), "Invalid tokenId:Token does not exist");
        _transfer(doris, _to, _tokenId);
        _handlepaymentnew(msg.value);
    }

    function _handlepaymentnew(uint256 payment) public {
        (bool df, ) = payable(doris).call{value: dorisfees*payment/100}("");
        require(df, "Doris fee error");
        (bool ap, ) = payable(artist).call{value: address(this).balance}("");
        require(ap, "Artist payment error");
    }

    function _handlepaymentold(address from, uint256 payment) public payable {
        (bool df, ) = payable(doris).call{value: dorisfees*payment/100}("");
        require(df, "Doris fee error");
        (bool af, ) = payable(artist).call{value: artistfees*payment/100}("");
        require(af, "Artist fee error");
        (bool ap, ) = payable(from).call{value: address(this).balance}("");
        require(ap, "Seller payment error");
    }

    function transferTokenFrom(address _from, address _to, uint256 _tokenId) public payable unpaused {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "ERC721: transfer caller is not owner nor approved");
        if(msg.sender != ownerOf(_tokenId)){
            _handlepaymentold(_from,msg.value);
        }
        transferFrom(_from, _to, _tokenId);
    }

    function approve(address _to, uint256 _tokenId) public virtual override(ERC721) {
        address owner = ERC721.ownerOf(_tokenId);
        require(_to != owner, "ERC721: approval to current owner");
        require(msg.sender == owner, "ERC721: approve caller is not owner nor approved for all");
        _approve(_to, _tokenId);
    }

}
