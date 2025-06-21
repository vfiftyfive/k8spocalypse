#!/usr/bin/env fish

# Script to clear MongoDB database and Redis cache
# Usage: ./clear-db-and-cache.fish

echo "🧹 Clearing MongoDB and Redis data..."

# Clear MongoDB jokes collection
echo "📚 Clearing MongoDB jokes collection..."
kubectl exec -n dev mongodb-0 -c mongod -- mongosh --quiet --eval "use jokesdb; db.auth('demo', 'spectrocloud'); db.jokes.deleteMany({})" 2>/dev/null

set jokes_deleted $status
if test $jokes_deleted -eq 0
    echo "✅ MongoDB jokes collection cleared"
else
    echo "⚠️  Failed to clear MongoDB jokes collection"
end

# Clear Redis cache
echo "🗄️  Clearing Redis cache..."
kubectl exec -n dev redis-0 -c redis -- redis-cli FLUSHALL 2>/dev/null

set redis_cleared $status
if test $redis_cleared -eq 0
    echo "✅ Redis cache cleared"
else
    echo "⚠️  Failed to clear Redis cache"
end

# Verify the cleanup
echo ""
echo "🔍 Verification:"

# Check MongoDB count
set joke_count (kubectl exec -n dev mongodb-0 -c mongod -- mongosh --quiet --eval "use jokesdb; db.auth('demo', 'spectrocloud'); db.jokes.countDocuments()" 2>/dev/null | tail -1)
echo "📊 MongoDB jokes count: $joke_count"

# Check Redis keys
set redis_keys (kubectl exec -n dev redis-0 -c redis -- redis-cli DBSIZE 2>/dev/null | awk '{print $2}')
echo "🔑 Redis keys count: $redis_keys"

echo ""
echo "🎯 Database and cache clearing complete!"
echo "💡 Note: The joke-worker will now generate new jokes (slow path) until 20 jokes are accumulated" 