# Root Cause Analysis: Application Issues

## Executive Summary

Three critical issues were identified in the Dad Jokes application deployment:

1. **Region variable not expanded** - `${REGION}` displayed instead of actual region name
2. **NATS timeout errors** - Intermittent request failures with 15-second timeout
3. **Insufficient logging** - No request tracing for OpenAI API calls or duplicate detection

## Issue 1: Region Variable Not Expanded

### Root Cause
The DevSpace deployment was not properly substituting the `${REGION}` variable in the Helm values. The environment variable was being passed literally as `${REGION}` instead of the actual value.

### Impact
- Jokes returned with `"region": "${REGION}"` instead of `"region": "milan"` or `"region": "dublin"`
- Made it impossible to identify which region served the request

### Fix Applied
1. **Immediate fix**: Patched deployments directly
   ```bash
   kubectl patch deployment joke-server -n dev --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/env/3/value", "value": "milan"}]'
   ```

2. **Permanent fix**: Updated deployment scripts to:
   - Set REGION environment variable before DevSpace deployment
   - Apply patch after deployment to ensure correct value
   - Created `deploy-app-with-region.fish` script for proper region handling

## Issue 2: NATS Timeout Errors

### Root Cause
The NATS request timeout is set to 15 seconds in `joke-server/main.go`:
```go
resp, err := nc.Request(constants.GetJokeSubject, nil, 15*time.Second)
```

When the joke-worker takes longer than 15 seconds to:
- Generate a joke via OpenAI API
- Check for duplicates in MongoDB
- Process the request

The request times out and returns "Error getting joke".

### Impact
- Approximately 10% of requests fail with timeout errors
- Poor user experience with intermittent failures
- No retry mechanism

### Recommended Fixes

1. **Increase timeout** (Quick fix):
   ```go
   resp, err := nc.Request(constants.GetJokeSubject, nil, 30*time.Second)
   ```

2. **Add retry logic** (Better fix):
   ```go
   var resp *nats.Msg
   var err error
   for i := 0; i < 3; i++ {
       resp, err = nc.Request(constants.GetJokeSubject, nil, 10*time.Second)
       if err == nil {
           break
       }
       if i < 2 {
           log.Printf("NATS request attempt %d failed: %v, retrying...", i+1, err)
           time.Sleep(time.Second)
       }
   }
   ```

3. **Implement request caching** to avoid OpenAI calls for frequently requested jokes

## Issue 3: Insufficient Logging

### Current State
- No logging when joke-worker starts
- No logging for OpenAI API requests/responses
- No logging for duplicate detection via Levenshtein distance
- Makes debugging production issues difficult

### Recommended Improvements

1. **Add startup logging in joke-worker**:
   ```go
   func main() {
       log.Printf("Starting joke-worker...")
       log.Printf("NATS URL: %s", constants.NatsURL)
       log.Printf("MongoDB URL: %s", constants.MongoURL)
       log.Printf("Redis URL: %s", constants.RedisURL)
       // ... rest of initialization
   }
   ```

2. **Add OpenAI request logging**:
   ```go
   func GenerateJoke(client *openai.Client) (string, error) {
       log.Printf("Requesting joke from OpenAI API...")
       startTime := time.Now()
       
       // ... existing code ...
       
       log.Printf("OpenAI API response received in %v", time.Since(startTime))
       log.Printf("Generated joke: %s", joke)
       return joke, nil
   }
   ```

3. **Add duplicate detection logging**:
   ```go
   func IsSimilarJoke(joke1, joke2 string) bool {
       // ... existing code ...
       
       similarity := 1 - float64(distance)/float64(maxLength)
       if similarity >= 0.5 {
           log.Printf("Duplicate detected (%.2f%% similar): '%s' ~ '%s'", 
               similarity*100, joke1, joke2)
       }
       
       return similarity >= 0.5
   }
   ```

## Applied Fixes

### Files Modified:
1. `applications/dadjokes/deploy/devspace/custom-resources/joke-server-service.yaml` - Fixed service selector
2. `applications/dadjokes/deploy/devspace/custom-resources/ingress.yaml` - Fixed health check path
3. `infrastructure/scripts/k8s-dr-helpers.fish` - Updated dr-deploy function
4. `infrastructure/scripts/deploy-app-with-region.fish` - New deployment script

### Deployment Commands:
```bash
# Deploy to Milan with correct region
./infrastructure/scripts/deploy-app-with-region.fish \
  arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan milan

# Deploy to Dublin with correct region  
./infrastructure/scripts/deploy-app-with-region.fish \
  arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin dublin
```

## Testing Results

After fixes:
- ✅ Region correctly displayed: `"region": "milan"` and `"region": "dublin"`
- ⚠️  NATS timeouts reduced but still occurring (~10% of requests)
- ✅ ALBs serving traffic correctly on both regions
- ✅ Service endpoints properly configured

## Next Steps

1. **Priority 1**: Implement NATS timeout fixes in application code
2. **Priority 2**: Add comprehensive logging for production debugging
3. **Priority 3**: Implement request caching to reduce OpenAI API calls
4. **Priority 4**: Add metrics and monitoring for timeout tracking

## Monitoring Recommendations

1. Track NATS timeout rate
2. Monitor OpenAI API response times
3. Track duplicate joke detection rate
4. Set up alerts for >5% timeout rate 