const { ethers } = require("hardhat")


async function main() {
    const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();
    //const chainId = await getChainId();
    const [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    const weatherNFTContract = await ethers.getContractFactory('weatherNFT');
    console.log("About to deploy");
    const weatherNFT = await weatherNFTContract.deploy(0xCa87445C20dfE7ad201cF7F01B75EEaE2640536d, owner.address, addr1.address,  addr2.address, 86400, "weatherNFT", "WNFT");
    await weatherNFT.deployed();
    log('NFT contract deployed to', weatherNFT.address);


    const WEATHERNFT = new ethers.Contract(weatherNFT.address, weatherNFT.interface, signer);
    //const networkName = networkConfig[chainId]['name'];
    //log('verify with: \n npx hardhat verify --network', networkName, WEATHERNFT.adress)
}
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
