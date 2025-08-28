# Phase 5.2: Real-Time Event Streaming - Planning Document

**Date:** 2025-08-28  
**Phase:** 5.2 - Real-Time Event Streaming  
**Status:** Planning Complete - Ready for Implementation  
**Estimated Effort:** 5-7 days  

## Problem Statement

The current SWE-bench-Elixir system has basic Phoenix.PubSub integration in the LiveView web interface, but lacks comprehensive real-time event streaming for evaluation lifecycle events, dataset updates, and WebSocket coordination. This limitation prevents users from receiving instant updates about evaluation progress, completion status, and system events, resulting in a suboptimal user experience that relies on manual refresh or polling mechanisms.

### Impact Analysis

**Current Pain Points:**
- No real-time visibility into evaluation progress and execution stages
- Manual refresh required to see updated results and system status
- No event sourcing capabilities for debugging and audit trails
- Limited scalability for concurrent users expecting real-time updates
- Disconnected experience between Phase 4 advanced capabilities and user interface

**Business Impact:**
- Reduced user engagement due to poor real-time experience
- Increased server load from polling-based approaches
- Limited ability to provide meaningful progress feedback during long-running evaluations
- Reduced confidence in system reliability without real-time status updates

## Solution Overview

Implement a comprehensive Phoenix.PubSub-based real-time event streaming system that provides instant updates for all evaluation lifecycle events, dataset changes, and system status. The solution leverages existing Phoenix infrastructure while adding event sourcing, WebSocket optimization, and integration with Phase 4 distributed capabilities.

### Design Decisions

**1. Channel Architecture:**
- Hierarchical topic structure: `evaluation:{user_id}`, `dataset:public`, `system:health`
- Event namespacing with clear separation between admin and public channels
- Integration with existing LiveView PubSub subscriptions

**2. Event Sourcing:**
- Event store using PostgreSQL with dedicated events table
- Event replay capabilities for debugging and system recovery
- Append-only event log with proper indexing and partitioning

**3. WebSocket Optimization:**
- Connection pooling and lifecycle management through Phoenix.Channels
- Compression for large payloads using built-in WebSocket compression
- Rate limiting and backpressure handling at the channel level

**4. Integration Points:**
- Existing `SweBench.Pipeline.ResultStreamer` for progress broadcasting
- Phase 4 distributed evaluation components for cluster-wide events
- LiveView components for seamless real-time UI updates

## Agent Consultations Performed

**Note:** Subagent consultation was attempted but the system is not configured in this codebase. The following technical guidance is based on Phoenix.PubSub best practices, existing codebase patterns, and production real-time system experience.

### Technical Architecture Guidance

**Phoenix.PubSub Channel Structure:**
```elixir
# Evaluation lifecycle events
"evaluation:#{evaluation_id}"           # Specific evaluation updates
"evaluation:user:#{user_id}"            # User-specific evaluation events
"evaluation:repository:#{repo}"         # Repository-specific events
"evaluation:global"                     # Public evaluation events

# Dataset and system events  
"dataset:tasks"                         # Task instance updates
"dataset:repositories"                  # Repository status changes
"dataset:versions"                      # Dataset version releases
"system:health"                         # System health and metrics
"system:admin"                          # Admin-only system events
```

**Event Sourcing Implementation:**
- Dedicated `events` table with `event_type`, `aggregate_id`, `payload`, `metadata`
- Event versioning with schema evolution support
- Idempotent event processing with duplicate detection
- Time-based partitioning for efficient storage and querying

**WebSocket Optimization:**
- Phoenix.Channels for connection management and authentication
- Per-user connection tracking with graceful cleanup
- Selective subscription patterns to minimize bandwidth
- Compression for payloads over 1KB using deflate

## Technical Details

### File Structure

```
lib/swe_bench/
├── event_streaming/
│   ├── event_store.ex                  # Event sourcing storage
│   ├── event_publisher.ex              # PubSub event broadcasting  
│   ├── event_subscriber.ex             # Event subscription management
│   ├── evaluation_events.ex            # Evaluation lifecycle events
│   ├── dataset_events.ex               # Dataset and repository events
│   └── system_events.ex                # System health and admin events
├── channels/
│   ├── evaluation_channel.ex           # Evaluation-specific WebSocket channel
│   ├── dataset_channel.ex              # Dataset updates channel
│   └── system_channel.ex               # System health and admin channel
└── event_streaming.ex                  # Main module and API

lib/swe_bench_web/
├── channels/
│   ├── user_socket.ex                  # WebSocket authentication and routing
│   └── presence.ex                     # User presence tracking
└── live/
    └── components/
        ├── real_time_progress.ex       # Real-time progress indicator
        ├── live_evaluation_status.ex   # Live evaluation status display
        └── event_feed.ex               # System event feed component
```

### Core Dependencies

**Existing Dependencies (Already Available):**
- `phoenix` - WebSocket and PubSub infrastructure
- `phoenix_live_view` - Real-time UI updates
- `phoenix_pubsub` - Event broadcasting system
- `ecto` - Database integration for event storage
- `jason` - JSON serialization for event payloads

**New Dependencies (If Required):**
- Consider `eventstore` for advanced event sourcing (optional)
- Consider `phoenix_presence` for user tracking (likely already available)

### Event Channel Architecture

```elixir
# Evaluation Events
%{
  type: "evaluation_started",
  aggregate_id: evaluation_id,
  data: %{
    user_id: user_id,
    repository: "phoenix",
    task_count: 150,
    estimated_duration: "30 minutes"
  },
  metadata: %{
    timestamp: DateTime.utc_now(),
    version: 1,
    source: "evaluation_coordinator"
  }
}

# Progress Events  
%{
  type: "evaluation_progress",
  aggregate_id: evaluation_id,
  data: %{
    completed_tasks: 45,
    total_tasks: 150,
    current_stage: "container_evaluation",
    progress_percentage: 30.0,
    estimated_remaining: "21 minutes"
  },
  metadata: %{
    timestamp: DateTime.utc_now(),
    sequence: 12
  }
}

# Completion Events
%{
  type: "evaluation_completed",
  aggregate_id: evaluation_id,
  data: %{
    final_score: 87.5,
    task_results: %{successful: 142, failed: 8},
    duration: "28 minutes",
    result_url: "/evaluations/#{evaluation_id}/results"
  },
  metadata: %{
    timestamp: DateTime.utc_now(),
    final: true
  }
}
```

### WebSocket Connection Management

**Authentication Integration:**
- Leverage existing `SweBench.Accounts` for user authentication
- Token-based authentication for WebSocket connections
- Role-based channel access (admin vs public channels)

**Connection Lifecycle:**
- Automatic reconnection with exponential backoff
- Graceful degradation when WebSocket unavailable
- Connection health monitoring and recovery

**Scalability Considerations:**
- Connection pooling across multiple Phoenix nodes
- Event distribution using Phoenix.PubSub.PG2 for cluster awareness
- Rate limiting per user to prevent abuse

## Success Criteria

### Functional Requirements
1. **Real-time evaluation updates:** Users receive instant progress updates during evaluation execution
2. **Event replay capability:** Admin users can replay events for debugging and audit purposes  
3. **WebSocket resilience:** Connections automatically recover from network interruptions
4. **Performance scalability:** System handles 1000+ concurrent WebSocket connections
5. **Integration completeness:** All Phase 4 evaluation stages broadcast appropriate events

### Performance Metrics
1. **Event delivery latency:** < 100ms for local events, < 500ms for distributed events
2. **WebSocket connection capacity:** Support 1000+ concurrent connections per node
3. **Event throughput:** Process 10,000+ events/minute without backpressure
4. **Memory efficiency:** Event store memory usage < 500MB for 1M events
5. **Database performance:** Event queries return results in < 50ms

### User Experience
1. **Immediate feedback:** Progress indicators update in real-time during evaluation
2. **Connection transparency:** Users unaware of WebSocket reconnections
3. **Selective updates:** Users receive only relevant events based on subscriptions
4. **Admin visibility:** Admin users have complete system event visibility
5. **Public dashboard:** Public users see aggregate system activity in real-time

## Implementation Plan

### Step 1: Event Store Foundation (Day 1)
1. **Database schema design:**
   - Create `events` table with proper indexing
   - Add partitioning strategy for time-based queries
   - Create aggregate tracking tables for replay

2. **Core event store module:**
   - Implement `SweBench.EventStreaming.EventStore`
   - Add event appending with idempotency guarantees
   - Build event querying with filtering and pagination

3. **Basic event types:**
   - Define evaluation, dataset, and system event schemas
   - Create event serialization and validation functions
   - Add event versioning support for schema evolution

### Step 2: PubSub Event Broadcasting (Day 2)
1. **Event publisher implementation:**
   - Create `SweBench.EventStreaming.EventPublisher`
   - Add topic-based broadcasting with hierarchical channels
   - Integrate with existing Phoenix.PubSub infrastructure

2. **Event subscriber management:**
   - Implement `SweBench.EventStreaming.EventSubscriber`
   - Add subscription filtering and routing logic
   - Create subscription lifecycle management

3. **Integration with existing pipeline:**
   - Modify `SweBench.Pipeline.ResultStreamer` to emit events
   - Add event broadcasting to distributed evaluation components
   - Ensure Phase 4 components publish appropriate events

### Step 3: WebSocket Channel Implementation (Day 3)
1. **Phoenix.Channels setup:**
   - Create evaluation, dataset, and system channels
   - Implement authentication and authorization logic
   - Add connection tracking and presence management

2. **User socket configuration:**
   - Configure WebSocket routing in `SweBenchWeb.UserSocket`
   - Add token-based authentication for connections
   - Implement graceful connection handling

3. **Channel event handling:**
   - Add event subscription management per channel
   - Implement event filtering based on user permissions
   - Add rate limiting and backpressure handling

### Step 4: LiveView Integration (Day 4)
1. **Real-time components:**
   - Create progress indicators that subscribe to events
   - Build live evaluation status displays
   - Add system event feed for admin users

2. **Existing LiveView enhancement:**
   - Update `SweBenchWeb.DashboardLive` for real-time events
   - Enhance admin evaluation LiveView with progress streaming
   - Add WebSocket fallback for critical updates

3. **User experience optimization:**
   - Implement smooth progress animations
   - Add toast notifications for important events  
   - Create loading states during WebSocket connection

### Step 5: Event Sourcing and Replay (Day 5)
1. **Event replay infrastructure:**
   - Add event replay functionality to event store
   - Create admin interface for event debugging
   - Implement event stream rebuilding capabilities

2. **Event sourcing patterns:**
   - Add aggregate rebuilding from event streams
   - Create event projection for common queries
   - Implement event compaction for storage efficiency

3. **Debugging and monitoring:**
   - Add event stream visualization tools
   - Create monitoring dashboards for event throughput
   - Implement alerts for event processing failures

### Step 6: Performance Optimization and Testing (Days 6-7)
1. **Load testing:**
   - Test WebSocket connection limits
   - Measure event processing throughput
   - Validate performance under concurrent load

2. **Optimization:**
   - Tune PubSub configuration for high throughput
   - Optimize database queries and indexing
   - Add caching for frequently accessed events

3. **Error handling and resilience:**
   - Implement comprehensive error handling
   - Add circuit breakers for external dependencies
   - Create graceful degradation strategies

## Notes/Considerations

### Edge Cases
1. **WebSocket connection failures:** Implement queued event delivery for reconnection
2. **Event ordering guarantees:** Use sequence numbers and event timestamps
3. **Large event payloads:** Implement pagination for events with large datasets
4. **Clock synchronization:** Handle timestamp skew in distributed environments
5. **Database partitioning:** Plan for automatic partition management

### Performance Implications
1. **Event store growth:** Implement event archiving and cleanup policies
2. **PubSub scalability:** Monitor topic subscription patterns for optimization
3. **WebSocket memory usage:** Track connection memory consumption
4. **Database connection pooling:** Ensure adequate connections for event queries
5. **Network bandwidth:** Monitor event payload sizes and compression ratios

### Scalability Requirements
1. **Multi-node deployment:** Ensure events propagate across Phoenix cluster
2. **Database sharding:** Plan for event store horizontal scaling
3. **Connection distribution:** Balance WebSocket connections across nodes
4. **Event processing:** Design for horizontal scaling of event consumers
5. **Monitoring integration:** Ensure observability across distributed system

### Integration Considerations
1. **Phase 4 compatibility:** Ensure all advanced features emit appropriate events  
2. **Authentication integration:** Leverage existing user management system
3. **Database consistency:** Coordinate event storage with existing data models
4. **LiveView patterns:** Follow existing component architecture patterns
5. **Testing integration:** Ensure event streaming works with existing test suite

## Risk Assessment

### Technical Risks
1. **WebSocket scaling limits:** Monitor connection limits and implement load balancing
2. **Event store performance:** Watch for database bottlenecks with high event volume
3. **Memory consumption:** Track event buffering and subscription memory usage
4. **Network partitions:** Implement proper handling of distributed system failures

### Mitigation Strategies
1. **Gradual rollout:** Enable event streaming progressively across features
2. **Monitoring:** Implement comprehensive metrics and alerting
3. **Fallback mechanisms:** Provide polling-based fallbacks for critical features
4. **Load testing:** Validate performance under realistic production conditions

This planning document provides a comprehensive roadmap for implementing real-time event streaming in Phase 5.2, building upon the existing Phoenix.PubSub infrastructure while adding advanced event sourcing, WebSocket optimization, and seamless integration with the LiveView web interface and Phase 4 advanced capabilities.