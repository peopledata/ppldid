# `did:ppld` Resolver

This library is intended to use [PPLDID](https://github.com/peopledata/ppldid) as fully self-managed Decentralized Identifiers and wrap them in a DID Document

It supports the proposed [Decentralized Identifiers](https://w3c.github.io/did-core/#identifier) spec from the [W3C Credentials Community Group](https://w3c-ccg.github.io/).

It requires the [`did-resolver`](https://github.com/decentralized-identity/did-resolver) library, which is the primary interface for resolving DIDs. Also it is dependent on a hosted resolver that can resolve PPLDID DIDs. Such an implementation can be found here: https://github.com/peopledata/ppldid

There is also a publicly available resolver at https://ppld-resolver.peopledata.org.cn, which is used as fallback resolver within this library.

## DID method

The `did:ppld` method links the identifier cryptographically to the DID Document and through also cryptographically linked provenance information in a public log it ensures resolving to the latest valid version of the DID Document. Read more about PPLDID at https://github.com/peopledata/ppldid

Example:    
`did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh`

## Installation

Node.js and npm are prerequisites for installation.

```bash
npm install ppldid-did-resolver
```

## Usage

The library presents a `resolve()` functions that returns a `Promise` returning the  DID document. It is not meant to be used directly but through the **`did-resolver`** aggregator.    

```javascript
const { Resolver } = require('did-resolver');
const ppldid = require('ppldid-did-resolver');

const resolver = new Resolver({
  ...ppldid.getResolver()
});

// resolve test-did
resolver.resolve('did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh').then(data =>
  console.log(JSON.stringify(data, undefined, 2))
);
```

## DID Document

The did resolver takes the identifier and queries existing PPLDID repositories to retrieve a DID document with the hash representation of the given identifier.

A minimal DID document using the above sample DID looks like this:

```
{
  "didResolutionMetadata": {},
  "didDocument": {
    "@context": "https://www.w3.org/ns/did/v1",
    "id": "did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
    "verificationMethod": [
      {
        "id": "did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
        "type": "Ed25519VerificationKey2020",
        "controller": "did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
        "publicKeyBase58": "z6MusYB5iT5krCHYsZ76EzBaTdRwGKsaBhMcSbrXaPJgkuRQ"
      }
    ],
    "keyAgreement": [
      {
        "id": "did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
        "type": "Ed25519VerificationKey2020",
        "controller": "did:ppld:zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
        "publicKeyBase58": "z6Mv7EYihbAat6Wq7GsjNsjcxt58dZT8fmsRjQGTkYamYrjB"
      }
    ],
    "service": [
      {
        "simple": "example"
      }
    ]
  },
  "didDocumentMetadata": {
    "did": "zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
    "registry": "https://ppldid.peopledata.org.cn",
    "log_hash": "zQmVwMvovLy5KNYHHVHQ1wv8J7y9L6UPE8eyU4tzypFWtYe",
    "log": [
      {
        "ts": 1641224736,
        "op": 2,
        "doc": "zQmaBZTghndXTgxNwfbdpVLWdFf6faYE4oeuN2zzXdQt1kh",
        "sig": "z3Kb5qeReCqr3ftxpf2i5UypUwrzrVkyspMtaDcb6e9YdHVSptcAFgvwbgk3qWqspTcGiKDYKXZZh8g6XyM2WPmNp",
        "previous": []
      },
      {
        "ts": 1641224736,
        "op": 0,
        "doc": "zQmT8SG7a238bF7wdV7LdrEAQpimqhKGor7CQsjtCYdZdTS",
        "sig": "z63hu8LseptBrvB2kEDwhPP35sBj7JDDJsEDW85cjRkrjjac9ZV3HxPW9NVKewHcQYwrVLVsnDCcm1RjbEARE5rJU",
        "previous": []
      }
    ],
    "document_log_id": 0,
    "termination_log_id": 1
  }
}
```

&nbsp;    

## License

[MIT License]
