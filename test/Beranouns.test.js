const {ethers} = require('hardhat')
const { expect } = require('chai');


describe('Beranouns', function () {
    this.beforeAll(async () => {
        const [owner, ...otherAccounts] = await ethers.getSigners();
        this.owner = owner;
        this.otherAccounts = otherAccounts;
        this.Beranouns = await ethers.getContractFactory('Beranouns');
        this.beranouns = await this.Beranouns.deploy(
            'Beranouns',
            'BRNS',
            await owner.getAddress()
        );
    });

    it('Should set config correctly when deployed', async () => {
        const name = await this.beranouns.name();
        const symbol = await this.beranouns.symbol();
        const feesCollector = await this.beranouns.feesCollector();
        expect(name).to.equal('Beranouns');
        expect(symbol).to.equal('BRNS');
        expect(feesCollector).to.equal(await this.owner.getAddress());
    });

    it('Should allow owner to pause', async () => {
        await this.beranouns.pause();
        const state = await this.beranouns.paused();
        expect(state).to.be.true;
    });

    it('Should allow owner to unpause', async () => {
        await this.beranouns.unpause();
        const state = await this.beranouns.paused();
        expect(state).to.be.false;
    });

    it("Should allow the owner to set specific prices for components", async () => {

    })

    it("should allow minting emojis", async () => {
        const tx = await this.beranouns.mint(
            "🐻",
            "🐻",
             3600 * 24 * 365,
             await this.owner.getAddress(),
             await this.owner.getAddress()
        )
        console.log("done")
    })
});
