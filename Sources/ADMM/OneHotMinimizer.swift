/// Implements a "one hot" binary vector
public class OneHotMinimizer: Minimizer {
    /// Associated factor node
    public let factor: Factor
    
    /// Edges over which to enforce the one-hot property
    private let edges: [Edge]
    
    /// Algorithm-specific implementation
    private let _minimize: ([Edge]) -> Void
    
    /// Creates the minimizer
    ///
    /// - Parameters:
    ///   - factor: associated factor node
    ///   - vars: variables over which to enforce the one-hot property
    ///
    /// - Precondition: `vars` is non-empty
    public init(factor: Factor, vars: [Variable]) {
        self.factor = factor
        
        edges = vars.map {
            $0.createEdge()
        }
        
        _minimize = vars[0].twa ? OneHotMinimizer._minimizeTWA : OneHotMinimizer._minimizeADMM
        
        //
        
        edges.forEach { connectEdge($0) }
    }
    
    /// Creates the minimizer with a new factor
    ///
    /// - Parameters:
    ///   - vars: variables over which to enforce the one-hot property
    ///
    /// - Precondition: `vars` is non-empty
    public convenience init(vars: [Variable]) {
        self.init(factor: vars[0].problem.addFactor(), vars: vars)
    }
    
    /// Implements the one-hot constraint
    public final func minimize() {
        _minimize(self.edges)
    }
    
    /// Sets the value of each edge to zero with a supplied weight
    ///
    /// - Parameters:
    ///   - edges: edges to zero-out
    ///   - weight: weight to associate with the 0
    private static func _zero(_ edges: [Edge], weight: ResultWeight) {
        edges.forEach {
            $0.setResult(Double.zero, weight: weight)
        }
    }
    
    /// Returns the edge from a list with the biggest incoming message
    ///
    /// - Parameter edges: edges to consider
    /// - Precondition: `edges` is non-empty
    private static func _findBiggest(_ edges: [Edge]) -> Edge {
        return edges.max { $0.msg <= $1.msg }!
    }
    
    /// Implements the constraint ignoring weights
    /// (biggest=1.0, rest=0.0; weight=standard)
    ///
    /// - Parameter edges: vector of edges over which to enforce the constraint
    private static func _minimizeADMM(_ edges: [Edge]) {
        let biggest = _findBiggest(edges)
        
        _zero(edges, weight: .std)
        biggest.setResult(1.0, weight: .std)
    }
    
    /// Implements the constraint with three classes of weights
    ///
    /// - Parameter edges: vector of edges over which to enforce the constraint
    private static func _minimizeTWA(_ edges: [Edge]) {
        let infOnEdges = edges.filter { $0.weight == .inf && $0.msg == 1.0 }
        
        // No known on (directly)
        if infOnEdges.isEmpty {
            // What about known off?
            let infOffEdges = edges.filter { $0.weight == .inf && $0.msg.isZero }
            
            if infOffEdges.count == (edges.count - 1) {
                // Since all but one are known off, remainder must be known on!
                for e in edges {
                    let result = e.weight == .inf ? 0.0 : 1.0
                    
                    e.setResult(result, weight: .inf)
                }
            } else if infOffEdges.count == edges.count {
                // all "known" OFF
                crash()
            } else {
                /* ignoring for performance reasons
                let infWeirdEdges = edges.filter { $0.weight == .inf && $0.msg != 0.0 }
                if !infWeirdEdges.isEmpty {
                    // "known" value other than OFF/ON
                    crash()
                } */
                
                let biggestRest: Edge
                
                // If possible, find biggest from amongst standard edges
                // (remainder would be zero-weight or inf-weight value=0)
                let stdEdges = edges.filter { $0.weight == .std }
                
                if stdEdges.isEmpty {
                    // So if no standard weight, must use zero-weight
                    // (to avoid contradicting potential known value=0)
                    let zeroEdges = edges.filter { $0.weight == .zero }
                    
                    biggestRest = _findBiggest(zeroEdges)
                } else {
                    biggestRest = _findBiggest(stdEdges)
                }
                
                //

                edges.forEach {
                    // Propagate inf-weight zero if supplied as such
                    let outgoingWeight: ResultWeight = ($0.weight == .inf ? .inf : .std)
                    
                    $0.setResult(Double.zero, weight: outgoingWeight)
                }
                biggestRest.setResult(1.0, weight: .std)
            }
        } else if infOnEdges.count == 1 {
            // A single known ON
            _zero(edges, weight: .inf)
            infOnEdges[0].setResult(1.0, weight: .inf)
        } else {
            // more than one "known" ON
            crash()
        }
    }
}