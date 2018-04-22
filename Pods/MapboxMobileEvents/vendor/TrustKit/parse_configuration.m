/*
 
 parse_configuration.m
 TrustKit
 
 Copyright 2016 The TrustKit Project Authors
 Licensed under the MIT license, see associated LICENSE file for terms.
 See AUTHORS file for the list of project authors.
 
 */

#import "TSKTrustKitConfig.h"
#import "parse_configuration.h"
#import "Pinning/TSKPublicKeyAlgorithm.h"
#import <CommonCrypto/CommonDigest.h>
#import "configuration_utils.h"

static SecCertificateRef certificateFromPEM(NSString *pem)
{
    // NOTE: multi-certificate PEM is not supported since this is for individual
    // trust anchor certificates.
    
    // Strip PEM header and footers. We don't support multi-certificate PEM.
    NSMutableString *pemMutable = [pem stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].mutableCopy;
    
    // Strip PEM header and footer
    [pemMutable replaceOccurrencesOfString:@"-----BEGIN CERTIFICATE-----"
                                withString:@""
                                   options:(NSStringCompareOptions)(NSAnchoredSearch | NSLiteralSearch)
                                     range:NSMakeRange(0, pemMutable.length)];
    
    [pemMutable replaceOccurrencesOfString:@"-----END CERTIFICATE-----"
                                withString:@""
                                   options:(NSStringCompareOptions)(NSAnchoredSearch | NSBackwardsSearch | NSLiteralSearch)
                                     range:NSMakeRange(0, pemMutable.length)];
    
    NSData *pemData = [[NSData alloc] initWithBase64EncodedString:pemMutable
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (CFDataRef)pemData);
    if (!cert)
    {
        [NSException raise:@"TrustKit configuration invalid" format:@"Failed to parse PEM certificate"];
    }
    return cert;
}


NSDictionary *parseTrustKitConfiguration(NSDictionary *trustKitArguments)
{
    // Convert settings supplied by the user to a configuration dictionary that can be used by TrustKit
    // This includes checking the sanity of the settings and converting public key hashes/pins from an
    // NSSArray of NSStrings (as provided by the user) to an NSSet of NSData (as needed by TrustKit)
    
    NSMutableDictionary *finalConfiguration = [[NSMutableDictionary alloc]init];
    finalConfiguration[kTSKPinnedDomains] = [[NSMutableDictionary alloc]init];
    
    
    // Retrieve global settings
    
    // Should we auto-swizzle network delegates
    NSNumber *shouldSwizzleNetworkDelegates = trustKitArguments[kTSKSwizzleNetworkDelegates];
    if (shouldSwizzleNetworkDelegates == nil)
    {
        // Default setting is NO
        finalConfiguration[kTSKSwizzleNetworkDelegates] = @(NO);
    }
    else
    {
        finalConfiguration[kTSKSwizzleNetworkDelegates] = shouldSwizzleNetworkDelegates;
    }
    
    
#if !TARGET_OS_IPHONE
    // OS X only: extract the optional ignorePinningForUserDefinedTrustAnchors setting
    NSNumber *shouldIgnorePinningForUserDefinedTrustAnchors = trustKitArguments[kTSKIgnorePinningForUserDefinedTrustAnchors];
    if (shouldIgnorePinningForUserDefinedTrustAnchors == nil)
    {
        // Default setting is YES
        finalConfiguration[kTSKIgnorePinningForUserDefinedTrustAnchors] = @(YES);
    }
    else
    {
        finalConfiguration[kTSKIgnorePinningForUserDefinedTrustAnchors] = shouldIgnorePinningForUserDefinedTrustAnchors;
    }
#endif
    
    // Retrieve the pinning policy for each domains
    if ((trustKitArguments[kTSKPinnedDomains] == nil) || ([trustKitArguments[kTSKPinnedDomains] count] < 1))
    {
        [NSException raise:@"TrustKit configuration invalid"
                    format:@"TrustKit was initialized with no pinned domains. The configuration format has changed: ensure your domain pinning policies are under the TSKPinnedDomains key within TSKConfiguration."];
    }
    
    
    for (NSString *domainName in trustKitArguments[kTSKPinnedDomains])
    {
        // Retrieve the supplied arguments for this domain
        NSDictionary *domainPinningPolicy = trustKitArguments[kTSKPinnedDomains][domainName];
        NSMutableDictionary *domainFinalConfiguration = [[NSMutableDictionary alloc]init];
        
        
        // Always start with the optional excludeSubDomain setting; if it set, no other TSKDomainConfigurationKey can be set for this domain
        NSNumber *shouldExcludeSubdomain = domainPinningPolicy[kTSKExcludeSubdomainFromParentPolicy];
        if (shouldExcludeSubdomain)
        {
            // Confirm that no other TSKDomainConfigurationKeys were set for this domain
            if ([[domainPinningPolicy allKeys] count] > 1)
            {
                [NSException raise:@"TrustKit configuration invalid"
                            format:@"TrustKit was initialized with TSKExcludeSubdomainFromParentPolicy for domain %@ but detected additional configuration keys", domainName];
            }
            
            // Store the whole configuration and continue to the next domain entry
            domainFinalConfiguration[kTSKExcludeSubdomainFromParentPolicy] = @(YES);
            finalConfiguration[kTSKPinnedDomains][domainName] = [NSDictionary dictionaryWithDictionary:domainFinalConfiguration];
            continue;
        }
        else
        {
            // Default setting is NO
            domainFinalConfiguration[kTSKExcludeSubdomainFromParentPolicy] = @(NO);
        }

        // Default setting is NO
        domainFinalConfiguration[kTSKIncludeSubdomains] = @(NO);            
        
        // Extract the optional expiration date setting
        NSString *expirationDateStr = domainPinningPolicy[kTSKExpirationDate];
        if (expirationDateStr != nil)
        {
            // Convert the string in the yyyy-MM-dd format into an actual date
            NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
            [dateFormat setDateFormat:@"yyyy-MM-dd"];
            NSDate *expirationDate = [dateFormat dateFromString:expirationDateStr];
            domainFinalConfiguration[kTSKExpirationDate] = expirationDate;
        }
        
        
        // Extract the optional enforcePinning setting
        NSNumber *shouldEnforcePinning = domainPinningPolicy[kTSKEnforcePinning];
        if (shouldEnforcePinning)
        {
            domainFinalConfiguration[kTSKEnforcePinning] = shouldEnforcePinning;
        }
        else
        {
            // Default setting is YES
            domainFinalConfiguration[kTSKEnforcePinning] = @(YES);
        }

        
        // Extract the optional disableDefaultReportUri setting
        NSNumber *shouldDisableDefaultReportUri = domainPinningPolicy[kTSKDisableDefaultReportUri];
        if (shouldDisableDefaultReportUri)
        {
            domainFinalConfiguration[kTSKDisableDefaultReportUri] = shouldDisableDefaultReportUri;
        }
        else
        {
            // Default setting is NO
            domainFinalConfiguration[kTSKDisableDefaultReportUri] = @(NO);
        }
        
        // Extract the optional additionalTrustAnchors setting
        NSArray *additionalTrustAnchors = domainPinningPolicy[kTSKAdditionalTrustAnchors];
        if (additionalTrustAnchors)
        {
            CFMutableArrayRef anchorCerts = CFArrayCreateMutable(NULL, (CFIndex)additionalTrustAnchors.count, &kCFTypeArrayCallBacks);
            NSInteger certIndex = 0; // used for logging error messages
            for (NSString *pem in additionalTrustAnchors) {
                SecCertificateRef cert = certificateFromPEM(pem);
                if (cert == nil) {
                    [NSException raise:@"TrustKit configuration invalid"
                                format:@"Failed to parse PEM-encoded certificate at index %ld for domain %@", (long)certIndex, domainName];
                }
                CFArrayAppendValue(anchorCerts, cert);
                certIndex++;
            }
            domainFinalConfiguration[kTSKAdditionalTrustAnchors] = [(__bridge NSMutableArray *)anchorCerts copy];
        }
        
        // Extract the list of public key algorithms to support and convert them from string to the TSKPublicKeyAlgorithm type
        NSArray<NSString *> *publicKeyAlgsStr = domainPinningPolicy[kTSKPublicKeyAlgorithms];
        if (publicKeyAlgsStr == nil)
        {
            [NSException raise:@"TrustKit configuration invalid"
                        format:@"TrustKit was initialized with an invalid value for %@ for domain %@", kTSKPublicKeyAlgorithms, domainName];
        }
        NSMutableArray *publicKeyAlgs = [NSMutableArray array];
        for (NSString *algorithm in publicKeyAlgsStr)
        {
            if ([kTSKAlgorithmRsa2048 isEqualToString:algorithm])
            {
                [publicKeyAlgs addObject:@(TSKPublicKeyAlgorithmRsa2048)];
            }
            else if ([kTSKAlgorithmRsa4096 isEqualToString:algorithm])
            {
                [publicKeyAlgs addObject:@(TSKPublicKeyAlgorithmRsa4096)];
            }
            else if ([kTSKAlgorithmEcDsaSecp256r1 isEqualToString:algorithm])
            {
                [publicKeyAlgs addObject:@(TSKPublicKeyAlgorithmEcDsaSecp256r1)];
            }
            else if ([kTSKAlgorithmEcDsaSecp384r1 isEqualToString:algorithm])
            {
                [publicKeyAlgs addObject:@(TSKPublicKeyAlgorithmEcDsaSecp384r1)];
            }
            else
            {
                [NSException raise:@"TrustKit configuration invalid"
                            format:@"TrustKit was initialized with an invalid value for %@ for domain %@", kTSKPublicKeyAlgorithms, domainName];
            }
        }
        domainFinalConfiguration[kTSKPublicKeyAlgorithms] = [NSArray arrayWithArray:publicKeyAlgs];
        
        
        // Extract and convert the report URIs if defined
        NSArray<NSString *> *reportUriList = domainPinningPolicy[kTSKReportUris];
        if (reportUriList != nil)
        {
            NSMutableArray<NSURL *> *reportUriListFinal = [NSMutableArray array];
            for (NSString *reportUriStr in reportUriList)
            {
                NSURL *reportUri = [NSURL URLWithString:reportUriStr];
                if (reportUri == nil)
                {
                    [NSException raise:@"TrustKit configuration invalid"
                                format:@"TrustKit was initialized with an invalid value for %@ for domain %@", kTSKReportUris, domainName];
                }
                [reportUriListFinal addObject:reportUri];
            }
            
            domainFinalConfiguration[kTSKReportUris] = [NSArray arrayWithArray:reportUriListFinal];
        }
        
        
        // Extract and convert the subject public key info hashes
        NSArray<NSString *> *serverSslPinsBase64 = domainPinningPolicy[kTSKPublicKeyHashes];
        NSMutableSet<NSData *> *serverSslPinsSet = [NSMutableSet set];
        
        for (NSString *pinnedKeyHashBase64 in serverSslPinsBase64) {
            NSData *pinnedKeyHash = [[NSData alloc] initWithBase64EncodedString:pinnedKeyHashBase64 options:(NSDataBase64DecodingOptions)0];
            
            if ([pinnedKeyHash length] != CC_SHA256_DIGEST_LENGTH)
            {
                // The subject public key info hash doesn't have a valid size
                [NSException raise:@"TrustKit configuration invalid"
                            format:@"TrustKit was initialized with an invalid Pin %@ for domain %@", pinnedKeyHashBase64, domainName];
            }
            
            [serverSslPinsSet addObject:pinnedKeyHash];
        }
        
        
        NSUInteger requiredNumberOfPins = [domainFinalConfiguration[kTSKEnforcePinning] boolValue] ? 2 : 1;
        if([serverSslPinsSet count] < requiredNumberOfPins)
        {
            [NSException raise:@"TrustKit configuration invalid"
                        format:@"TrustKit was initialized with less than %lu pins (ie. no backup pins) for domain %@. This might brick your App; please review the Getting Started guide in ./docs/getting-started.md", (unsigned long)requiredNumberOfPins, domainName];
        }
        
        // Save the hashes for this server as an NSSet for quick lookup
        domainFinalConfiguration[kTSKPublicKeyHashes] = [NSSet setWithSet:serverSslPinsSet];
        
        // Store the whole configuration
        finalConfiguration[kTSKPinnedDomains][domainName] = [NSDictionary dictionaryWithDictionary:domainFinalConfiguration];
    }
    
    // Lastly, ensure that we can find a parent policy for subdomains configured with TSKExcludeSubdomainFromParentPolicy
    for (NSString *domainName in finalConfiguration[kTSKPinnedDomains])
    {
        if ([finalConfiguration[kTSKPinnedDomains][domainName][kTSKExcludeSubdomainFromParentPolicy] boolValue])
        {
            // To force the lookup of a parent domain, we append 'a' to this subdomain so we don't retrieve its policy
            NSString *parentDomainConfigKey = getPinningConfigurationKeyForDomain([@"a" stringByAppendingString:domainName], finalConfiguration[kTSKPinnedDomains]);
            if (parentDomainConfigKey == nil)
            {
                [NSException raise:@"TrustKit configuration invalid"
                            format:@"TrustKit was initialized with TSKExcludeSubdomainFromParentPolicy for domain %@ but could not find a policy for a parent domain", domainName];
            }
        }
    }

    return [finalConfiguration copy];
}
