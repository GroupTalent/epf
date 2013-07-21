var get = Ember.get, set = Ember.set, isEqual = Ember.isEqual;

function mergeIfPresent(session, model, strategy) {
  if(!model) return null;
  return session.merge(model, strategy);
}

/**
  Merge strategy that merges on a per-field basis.

  Fields which have been editted by both parties will
  default to "ours".
*/
Ep.PerField = Ep.MergeStrategy.extend({

  init: function() {
    this.cache = Ep.ModelSet.create();
  },

  merge: function(ours, ancestor, theirs) {
    if(this.cache.contains(ours)) return ours;
    this.cache.addObject(theirs);
    ours.beginPropertyChanges();
    this.mergeAttributes(ours, ancestor, theirs);
    this.mergeRelationships(ours, ancestor, theirs);
    ours.endPropertyChanges();
    return ours;
  },

  mergeAttributes: function(ours, ancestor, theirs) {
    ours.eachAttribute(function(name, meta) {
      var oursValue = get(ours, name);
      var theirsValue = get(theirs, name);
      var originalValue = get(ancestor, name);
      if(oursValue === theirsValue) return;
      // keep "ours", only merge if ours hasn't changed
      if(oursValue === originalValue) {
        set(ours, name, theirsValue);
      }
    });
  },

  mergeRelationships: function(ours, ancestor, theirs) {
    var session = get(this, 'session');
    ours.eachRelationship(function(name, relationship) {
      if(relationship.kind === 'belongsTo') {
        var oursValue = get(ours, name);
        var theirsValue = get(theirs, name);
        var originalValue = get(ancestor, name);
        var merged = mergeIfPresent(session, theirsValue, this);
        // keep "ours", only merge if ours hasn't changed
        if(isEqual(oursValue, originalValue)) {
          set(ours, name, merged);
        }
      } else if(relationship.kind === 'hasMany') {
        var theirChildren = get(theirs, name);
        var ourChildren = get(ours, name);
        var originalChildren = get(ancestor, name);
        if(isEqual(ourChildren, originalChildren)) {
          // if we haven't modified the collection locally then
          // we replace
          var existing = Ep.ModelSet.create();
          existing.addObjects(ourChildren);

          theirChildren.forEach(function(model) {
            if(existing.contains(model)) {
              session.merge(model, this);
              existing.remove(model);
            } else {
              ourChildren.addObject(session.merge(model, this));
            }
          }, this);

          ourChildren.removeObjects(existing);
        } else {
          // otherwise just merge the models independent of
          // the relationship
          theirChildren.forEach(function(model) {
            session.merge(model, this);
          }, this);
        }
      }
    }, this);
  }

});
