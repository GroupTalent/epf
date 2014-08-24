`import setup from './_shared'`

describe "rest", ->

  adapter = null
  session = null

  beforeEach ->
    setup.apply(this)
    adapter = @adapter
    session = @session

  context 'simple model', ->

    beforeEach ->
      `class Post extends Coalesce.Model {}`
      Post.defineSchema
        typeKey: 'post'
        attributes:
          title: {type: 'string'}
      @App.Post = @Post = Post

      @container.register 'model:post', @Post


    it 'loads', ->  
      adapter.r['GET:/posts/1'] = posts: {id: 1, title: 'mvcc ftw'}
      session.load(@Post, 1).then (post) ->
        expect(post.id).to.eq("1")
        expect(post.title).to.eq('mvcc ftw')
        expect(adapter.h).to.eql(['GET:/posts/1'])


    it 'saves', ->
      adapter.r['POST:/posts'] = -> posts: {client_id: post.clientId, id: 1, title: 'mvcc ftw'}

      post = session.create('post')
      post.title = 'mvcc ftw'

      session.flush().then ->
        expect(post.id).to.eq("1")
        expect(post.title).to.eq('mvcc ftw')
        expect(adapter.h).to.eql(['POST:/posts'])


    it 'updates', ->
      adapter.r['PUT:/posts/1'] = -> posts: {id: 1, title: 'updated'}

      session.merge @Post.create(id: "1", title: 'test')

      session.load('post', 1).then (post) ->
        expect(post.title).to.eq('test')
        post.title = 'updated'
        session.flush().then ->
          expect(post.title).to.eq('updated')
          expect(adapter.h).to.eql(['PUT:/posts/1'])


    it 'updates multiple times', ->
      adapter.r['PUT:/posts/1'] = -> posts: {id: 1, title: 'updated'}

      post = session.merge @Post.create(id: "1", title: 'test')

      expect(post.title).to.eq('test')
      post.title = 'updated'

      session.flush().then ->
        expect(post.title).to.eq('updated')
        expect(adapter.h).to.eql(['PUT:/posts/1'])

        adapter.r['PUT:/posts/1'] = -> posts: {id: 1, title: 'updated again'}
        post.title = 'updated again'
        session.flush().then ->
          expect(post.title).to.eq('updated again')
          expect(adapter.h).to.eql(['PUT:/posts/1', 'PUT:/posts/1'])

          session.flush().then -> # NO-OP
            expect(post.title).to.eq('updated again')
            expect(adapter.h).to.eql(['PUT:/posts/1', 'PUT:/posts/1'])


    it 'deletes', ->
      adapter.r['DELETE:/posts/1'] = {}

      session.merge @Post.create(id: "1", title: 'test')

      session.load('post', 1).then (post) ->
        expect(post.id).to.eq("1")
        expect(post.title).to.eq('test')
        session.deleteModel(post)
        session.flush().then ->
          expect(post.isDeleted).to.be.true
          expect(adapter.h).to.eql(['DELETE:/posts/1'])


    it 'deletes multiple times in multiple flushes', ->
      adapter.r['DELETE:/posts/1'] = {}

      post1 = session.merge @Post.create(id: "1", title: 'thing 1')
      post2 = session.merge @Post.create(id: "2", title: 'thing 2')

      session.deleteModel post1

      session.flush().then ->

        expect(post1.isDeleted).to.be.true
        expect(post2.isDeleted).to.be.false

        adapter.r['DELETE:/posts/1'] = -> throw "already deleted"
        adapter.r['DELETE:/posts/2'] = {}

        session.deleteModel post2

        session.flush().then ->
          expect(post1.isDeleted).to.be.true
          expect(post2.isDeleted).to.be.true
          
    it 'creates, deletes, creates, deletes', ->
      post1 = session.create('post')
      post1.title = 'thing 1'
      
      adapter.r['POST:/posts'] = -> posts: {client_id: post1.clientId, id: 1, title: 'thing 1'}
      session.flush().then ->
        expect(post1.id).to.eq('1')
        expect(post1.title).to.eq('thing 1')
        session.deleteModel(post1)
        
        adapter.r['DELETE:/posts/1'] = {}
          
        session.flush().then ->
          expect(post1.isDeleted).to.be.true
          post2 = session.create('post')
          post2.title = 'thing 2'
          
          adapter.r['POST:/posts'] = -> posts: {client_id: post2.clientId, id: 2, title: 'thing 2'}
          
          session.flush().then ->
          
            adapter.r['DELETE:/posts/1'] = -> throw 'not found'
            adapter.r['DELETE:/posts/2'] = {}
          
            expect(post2.id).to.eq('2')
            expect(post2.title).to.eq('thing 2')
            session.deleteModel(post2)
            
            session.flush().then ->
              expect(post2.isDeleted).to.be.true
              expect(adapter.h).to.eql(['POST:/posts', 'DELETE:/posts/1', 'POST:/posts', 'DELETE:/posts/2'])
        
        


    it 'refreshes', ->
      adapter.r['GET:/posts/1'] = posts: {id: 1, title: 'something new'}

      session.merge @Post.create(id: "1", title: 'test')

      session.load(@Post, 1).then (post) ->
        expect(post.title).to.eq('test')
        expect(adapter.h).to.eql([])
        session.refresh(post).then (post) ->
          expect(post.title).to.eq('something new')
          expect(adapter.h).to.eql(['GET:/posts/1'])


    it 'finds', ->
      adapter.r['GET:/posts'] = (url, type, hash) ->
        expect(hash.data).to.eql({q: "aardvarks"})
        posts: [{id: 1, title: 'aardvarks explained'}, {id: 2, title: 'aardvarks in depth'}]

      session.find('post', {q: 'aardvarks'}).then (models) ->
        expect(models.length).to.eq(2)
        expect(adapter.h).to.eql(['GET:/posts'])


    it 'loads then updates', ->
      adapter.r['GET:/posts/1'] = posts: {id: 1, title: 'mvcc ftw'}
      adapter.r['PUT:/posts/1'] = posts: {id: 1, title: 'no more fsm'}

      session.load(@Post, 1).then (post) ->
        expect(post.id).to.eq("1")
        expect(post.title).to.eq('mvcc ftw')
        expect(adapter.h).to.eql(['GET:/posts/1'])

        post.title = 'no more fsm'
        session.flush().then ->
          expect(adapter.h).to.eql(['GET:/posts/1', 'PUT:/posts/1'])
          expect(post.title).to.eq('no more fsm')
          
    it 'loads with parameter', ->
      adapter.r['GET:/posts/1'] = (url, type, hash) ->
        expect(hash.data.invite_token).to.eq('fdsavcxz')
        posts: {id: 1, title: 'mvcc ftw'}
      session.load(@Post, 1, params: {invite_token: 'fdsavcxz'}).then (post) ->
        expect(post.id).to.eq("1")
        expect(post.title).to.eq('mvcc ftw')
        expect(adapter.h).to.eql(['GET:/posts/1'])
      