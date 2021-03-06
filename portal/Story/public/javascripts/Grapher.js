function Grapher(driver, name) {
  var self = this;
  self.driver = driver;
  self.name = self.nav = name;
  self.cache = {};
 
  self.resize = function () {
    // remove and resize container
    var panel = $("#panel");
    panel.empty();
    self.width = window.innerWidth - 195;
    self.height =  window.innerHeight - 100;
    panel.css('width', self.width);
    panel.css('height', self.height);
    
    // creates canvas
    self.paper = Raphael('panel', self.width, self.height); 
    for (var i = self.driver.start; i < self.driver.end; ++i) {
      $.ajax({url:'/cloud_data/' + self.name + '/' + i,
              async: false})
      .done(function (data) {
        self.cache[i] = JSON.parse(data);
      });
    }
    //$('html, body').animate({ scrollTop: self.top }, 0);
    
    // do paint
    self.paint();
  };

  self.right = function () {
    self.driver.start++;
    self.driver.end++;
    self.driver.resize();
  };
  
  self.left = function (k) {
    if (self.driver.start == 0) {
      return;
    }
    self.driver.start--;
    self.driver.end--;
    self.driver.resize();
  };
  
  self.paint = function () {
    var x_pad = 40;
    var y_pad = 60;
    var x_max = $('#panel').width() - 2*x_pad;
    var y_max = $('#panel').height() - 2*y_pad;
    
    // Draw x axis
    self.paper.path(['M', x_pad, y_pad + y_max, 'H', x_pad + x_max].join(' ')).attr({'stroke':'grey'});
    for (var i = self.driver.start; i < self.driver.end; ++i) {
      var dx = x_pad + x_max*(i-self.driver.start)/(self.driver.end-self.driver.start);
      var dy = y_pad + y_max;
      self.paper.text(dx, dy+10, self.cache[i].date).attr({'font-size':15});
    }
    
    // Draw y axis
    self.paper.path(['M', x_pad, y_pad, 'V', y_pad + y_max].join(' ')).attr({'stroke':'grey'});
    
    // plot nodes by day
    var n = {};
    var e = [];
    var xw = (1)/(self.driver.end-self.driver.start) * x_max;
    for (var i = self.driver.start; i < self.driver.end; ++i) {
      
      // find min-max weight for day
      var min_w = 1000000;
      var max_w = -1000000;
      $.each(self.cache[i].topics, function (i, n) {
        n.weight = parseFloat(n.weight);
        n.alpha = parseFloat(n.alpha);
        if (n.weight > max_w)
          max_w = n.weight;
        if (n.weight < min_w)
          min_w = n.weight;
      });
      
      // plot the nodes for each day
      $.each(self.cache[i].topics, function (j, topic) {
        var nx = (.8*Math.random()+.1)*xw + (i-self.driver.start)*xw + x_pad;
        var ny = y_max - (.9+.1*Math.random())*(topic.weight - min_w)/(max_w - min_w)*y_max + y_pad;
        var center = false;
        var p = self.paper.circle(nx, ny, topic.weight)
        .attr({
          'fill-opactiy' : 95,
          'fill' : center ? 'yellow': 'grey',
          'stroke' : center ? 'blue' : 'black',
          'stroke-width' : 2})
        .hover(
          function () {
            // bring current node to front
            this.toFront();

            // perform mini graph search
            var f = [{id:j, parent: null, weight:1}];
            var v = {};
            while (f.length) {
              var c = f.pop();
              if (c.parent != null) {
                var a = n[c.id];
                var b = n[c.parent];
                var s = ['M', a.px, a.py,
                         'C', a.px + .2*(b.px-a.px),
                              a.py + .8*(b.py-a.py),
                              b.px - .8*(b.px-a.px),
                              b.py - .2*(b.py-a.py),
                              b.px, b.py];
                e.push(
                  self
                  .paper.path(s.join(' '))
                  .attr({
                    'stroke':'black',
                    'stroke-width': c.weight*4,
                    'id': '#topic' + j})
                  .toBack());
                
              }
              for (k in n[c.id].edges) {
                if (typeof(n[k]) == 'undefined' ||
                    typeof(v[k]) != 'undefined' ||
                    n[c.id].edges[k]*c.weight < .6) continue;
                f.push({id:k, parent:c.id, weight:n[c.id].edges[k]*c.weight});
              }
              v[c.id] = 1;
            }
            var txt;
            for (var i = self.driver.start; i < self.driver.end; ++i) {
              if (typeof(self.cache[i].topics[j]) != 'undefined') {
                txt = self.cache[i].topics[j].words.join("\n");
                break;
              }
            }
            var tooltip = self.paper.text(n[j].px+70, n[j].py, txt).attr({
              'font-family' : "'Fugaz One', cursive",
              'font-size' : 15
            });
            var bb = tooltip.getBBox();
            e.push(self.paper.rect(bb.x, bb.y, bb.width+15, bb.height+15, 15).attr({fill:'white'}));
            e.push(tooltip);
            tooltip.toFront();
          },
          function () {
            while (e.length) {
              e.pop().remove();
            }
          }
        )
        .click(
          function () {
            // total flippin' hack right here. nothing about this says
            // good design
            $('#panel-top-button-name').innerHTML = 'Graph View';
            self.driver.add_context(new CloudTopic(self.driver, self.name, j));
          }
        )
        n[j] = {px:nx, py:ny, node:p, edges: topic.edges};
      });
    }
    // draw edges
    for (var i = self.driver.start; i < self.driver.end; ++i) {
      for (var j in self.cache[i].topics) {
        var topic = self.cache[i].topics[j];
        var a = n[j];
        for (var k in topic.edges) {
          if (typeof(n[k]) == 'undefined') continue;
          var b = n[k];
          var s = ['M', a.px, a.py, 'C', a.px + .2*(b.px-a.px),
                                         a.py + .8*(b.py-a.py),
                                         b.px - .8*(b.px-a.px),
                                         b.py - .2*(b.py-a.py),
                                         b.px, b.py];
          self.paper.path(s.join(' '))
          .attr({
            'stroke':'black',
            'stroke-width': .25})
          .toBack();
        }
        
      }
    }
  };
  function update_info(n) {
    var info_div = $('#'+info);
    info_div.empty();
    info_div.append('<h2><a href="javascript:void(0)" onclick="follow(\'' + name + '\', '+ n.id +')">'+ n.date + ': ' + n.title+'</a></h2>');
    var forward = [];
    var backward = [];
    var added = {};
    $.each(n.peers.sort(
      function (a, b) { return b.published - a.published; }),
      function (p, pn) {
        var title = pn.date + ': ' + pn.title;
        if (title in added) return;
        var li = '<li><small><a href="javascript:void(0)" onclick="follow(\'' + name + '\', '+ pn.id +')">' + title + '</a></small></li>';
        if (pn.published > n.published) {
          forward.push(li);
        }
        else {
          backward.push(li);
        }
        added[title] = 1;
      }
    );
    if (forward.length > 0) {
      info_div.append('<p><strong>Forward Edges</strong><ul>' + forward.join('') + '</ul></p>');
    }
    if (backward.length > 0) {
      info_div.append('<p><strong>Backward Edges</strong><ul>' + backward.join('') + '</ul></p>');
    }
    n.circle.toFront()
  };
  
  function update_container() {
    // convert strings to numbers
    $.each(data.nodes, function (i, n) {
      n.id = parseInt(n.id);
      n.published = parseInt(n.published);
      if (n.id == center) {
        n.center = true;
      }
      else {
        n.center = false;
      }
    });
    
    
    $.each(data.edges, function (i, e){
      e.a_id = parseInt(e.a_id);
      e.b_id = parseInt(e.b_id);
      e.weight = parseFloat(e.weight);
    });
    
    // sort the nodes for easier access/calculation of min/max
    data.nodes = data.nodes.sort(function (a, b) {
      return a.published - b.published;
    });
    
    var x_max = 700;
    var y_max = 420;
    var x_pad = 40;
    var y_pad = 30;
    
    // get the min and max for scaling purposes
    var tot = data.nodes.length;
    var min_t = data.nodes[0].published;
    var max_t = data.nodes[tot-1].published;
    if (min_t == max_t) return;
    
    // Creates canvas
    $('#'+container).empty();
    var paper = Raphael(container, x_max + 2*x_pad, y_max + 2*y_pad);
    
    // Draw x axis
    paper.path(['M', x_pad, y_pad + y_max, 'H', x_pad + x_max].join(' '))
         .attr({'stroke':'grey'});
    var d = 1;
    var start_d = new Date(new Date(1000*min_t).toDateString());
    while (start_d.getTime() + d*24*60*60*1000 < max_t*1000) {
      var nd = new Date(start_d.getTime() + d*24*60*60*1000);
      var dx = x_pad + x_max*(nd.getTime()/1000 - min_t)/(max_t-min_t);
      var dy = y_pad + y_max;
      paper.path(['M', dx, dy, 'v', 5]);
      if (nd.getDay() == 0) {
        paper.text(dx, dy+10, (nd.getMonth()+1) + '/' + nd.getDate() + '/' + nd.getFullYear())
      }
      d = d + 1;
    }
    
    // Draw y axis
    paper.path(['M', x_pad, y_pad, 'V', y_pad + y_max].join(' '))
         .attr({'stroke':'grey'});
    
    // Transform nodes into convenient, indexed form
    var nodes = [];
    var node_map = {};
    $.each(data.nodes, function (i, n) {
      n.height = 0;
      node_map[n.id] = nodes.length;
      nodes.push(n);
    });
    
    // Look at node edges for height
    $.each(data.edges, function (i, e) {
      nodes[node_map[e.a_id]].height += e.weight;
      node_map[e.b_id].height += e.weight;
    });
    
    // Calculate min/max height to scale
    var min_h = 1000000;
    var max_h = -1000000;
    $.each(nodes, function (i, n) {
      if (n.height > max_h)
        max_h = n.height;
      if (n.height < min_h)
        min_h = n.height;
    });
    
    // Plot the nodes
    var center_node;
    $.each(nodes, function (i, n) {
      // plot a circle for the node
      n.px = x_pad + ((n.published-min_t)/(max_t-min_t))*x_max;
      //n.py = y_pad / 2 + (i/tot)*y_max;
      n.py = y_pad + ((n.height-min_h)/(max_h-min_h))*y_max;
      n.radius = n.center ? 6 : 4;
      n.edges = [];
      n.peers = [];
      n.circle = paper.circle(n.px, n.py, n.radius).attr({
        'fill-opactiy' : 95,
        'fill' : n.center ? 'yellow': 'grey',
        'stroke' : n.center ? 'blue' : 'black',
        'stroke-width' : 2});
      if (n.center) center_node = n;
      
      // set a tooltip
      n.circle.attr({title:n.title});
      
      // set flag to denote clicked status
      n.circle.clicked = 0;
      
      // color when hovering
      n.circle.hover(
        function () {
          if (n.circle.clicked) return;
          
          $.each(n.edges, function (j, e) {
            e.attr({stroke:'red'}).toFront();
          });
          $.each(n.peers, function (j, p) {
            p.circle.attr({fill:'yellow', stroke:'red'}).toFront();
          });
          n.circle.attr({fill:'yellow', stroke:'red'}).toFront();
          update_info(n);
        },
        function () {
          if (n.circle.clicked) return;
          
          $.each(n.edges, function (j, e) {
            e.attr({stroke:'black'}).toBack()
          });
          $.each(n.peers, function (j, p) {
            p.circle.attr({
              fill:p.center ? 'yellow': 'grey',
              stroke:p.center ? 'blue' : 'black'});
          });
          n.circle.attr({
            fill:n.center ? 'yellow': 'grey',
            stroke:n.center ? 'blue' : 'black'});
          $.each(nodes, function (j, p) { p.circle.toFront(); } );
          update_info(center_node);
        }
      );
      
      n.circle.click(
        function () {
          center_node = n;
          update_info(center_node)
        }
      );
      /*
      // make color sticky on click
      n.circle.click(
        function () {
          if (n.circle.clicked == 0) {
            $.each(n.edges, function (j, e) {
              e.attr({stroke:'blue'}).toFront();
              e.clicked = 1;
            });
            $.each(n.peers, function (j, p) {
              p.circle.attr({fill:'green', stroke:'blue'}).toFront();
              p.clicked = 1;
            });
            n.circle.clicked = 1;
            n.circle.attr({fill:'yellow', stroke:'blue'}).toFront();
          }
          else {
            $.each(n.edges, function (j, e) {
              e.attr({stroke:'black'}).toFront().toFront();
              e.clicked = 0;
            });
            $.each(n.peers, function (j, p) {
              p.circle.attr({fill:'grey', stroke:'black'});
              p.clicked = 0;
            });
            n.circle.clicked = 0;
            n.circle.attr({fill:'grey', stroke:'black'});
          }
        }
      );
      */
    });
    
    // Plot the edges
    $.each(data.edges, function (i, e) {
      var a = nodes[node_map[e.a_id]];
      var b = nodes[node_map[e.b_id]];
      if (b.published < a.published) {
        var tmp = a;
        a = b;
        b = tmp;
      }
      var s = ['M', a.px, a.py, 'C', a.px + .2*(b.px-a.px),
                                     a.py + .8*(b.py-a.py),
                                     b.px - .8*(b.px-a.px),
                                     b.py - .2*(b.py-a.py),
                                     b.px, b.py];
      
      var p = paper.path(s.join(' ')).attr({stroke:'black', 'stroke-width': 1+e.cosign_freq*6});
      p.clicked = 0;
      p.hover(
        function () {
          if (p.clicked == 1) return;
          p.attr({stroke:'red'}).toFront();
          a.circle.attr({stroke:'red', fill:'yellow'}).toFront();
          b.circle.attr({stroke:'red', fill:'yellow'}).toFront();
        },
        function () {
          if (p.clicked == 1) return;
          p.attr({stroke:'black'}).toBack();
          a.circle.attr({
              fill:a.center ? 'yellow': 'grey',
              stroke:a.center ? 'blue' : 'black'});
          b.circle.attr({
              fill:b.center ? 'yellow': 'grey',
              stroke:b.center ? 'blue' : 'black'});          
          $.each(nodes, function (j, p) { p.circle.toFront(); } );
          update_info(center_node);
        }
      );
      p.click(
        function () {
          
        }
      );
      a.edges.push(p);
      b.edges.push(p);
      a.peers.push(b);
      b.peers.push(a);
    });
    $.each(nodes, function (j, p) { p.circle.toFront(); } );
    update_info(center_node);
  };
}