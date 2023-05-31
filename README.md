# Unitap prizetap contracts

## Deployment

To deploy the contract to a network, first set the constructor arguments in the ```scripts/args.js``` and then run the following bash commands:

```bash
$ npm i  
$ cp .env.example .env
```

Set the parameters in the ```.env``` file and then run the following command:

```bash
$ npm run deploy
```

## Get wallet info

You can use the following command to get wallet nounce and balance on all of the networks: 

```bash
$ npx hardhat account --address {wallet address}
```


