const args_abi = [
  "uint256", // Muon appId
  "tuple(uint256 x, uint8 parity) d", // Muon publicKey
  "address", // Muon address
  "address", // Muon gateway
  "address", // Admin
  "address" // Operator
]

const args_values = [
  "25465578003500666162514846212575646525905546121357887312364528382074876315425",
  {
    x: "0x701bdf32d0b912560fd66d60723f49caf1ec3e41a727eeb31124f653a9987e3b",
    parity: 1,
  },
  "0xAC00E96dc32241872cA03818F161855C3025f4fA",
  "0x4d7A51Caa1E79ee080A7a045B61f424Da8965A3c",
  "0xe9239a6Fe26985eB5B21DdaCDc904cDa7f7551a0",
  "0xB10f8E218A9cD738b0F1E2f7169Aa3c0897F2d83"
]

// const args_abi = [
//   "address", // ChainlinkVRFCoordinator address
//   "uint64", // ChainlinkVRFSubscriptionId
//   "bytes32", // ChainlinkKeyHash
//   "address", // Admin
//   "address" // Operator
// ]

// const args_values = [
//   "0xAE975071Be8F8eE67addBC1A82488F1C24858067",
//   941,
//   "0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd",
//   "0xe9239a6Fe26985eB5B21DdaCDc904cDa7f7551a0",
//   "0xB10f8E218A9cD738b0F1E2f7169Aa3c0897F2d83"
// ]

module.exports = {
  args_abi, args_values
}