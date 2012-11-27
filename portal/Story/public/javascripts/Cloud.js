function CloudAll(driver, name) {
  var self = this;
  self.driver = driver;
  self.name = self.nav = name;
  self.range = [];
  self.start = 0;
  self.end = 7;
  self.top = 0;
  self.cache = {};
  self.active = 7;
  
  self.resize = function () {
    for (var i = self.start; i < self.end; ++i) {
      self.addOffset(i, -1);
    }
    $('html, body').animate({ scrollTop: self.top }, 0);
  };

  self.right = function () {
    if (self.active > 0) {
      return;
    }
    self.active += 1;
    
    var first = self.range.shift();
    $('#'+first).remove();
    self.start++;
    self.end++;
    self.addOffset(self.end - 1, -1);
  };
  
  self.left = function (k) {
    if (self.active > 0 || self.start == 0) {
      return;
    }
    self.active += 1;
    
    var last = self.range.pop();
    $('#'+last).remove();
    self.start--;
    self.end--;
    self.addOffset(self.start, 0);
  };
  
  self.addOffset = function(offset, pos) {
    var addOffsetHandler = function (data) {
      data = JSON.parse(data);
      
      // out of range request
      if (Object.keys(data).length == 0) return;

      var panel = $("#panel");
      var date_id = 'panel-' + data.date;
      var top = 0;
      var width = panel.width() / (self.end - self.start);
      
      // create date container
      var date_container =
        $('<div/>', {'id': date_id})
        //.css('position', 'absolute')
        .css('float', 'left')
        .css('top', top)
        //.css('left', left)
        .css('height', panel.height())
        .css('width', width);
      if (pos == -1) {
        date_container.appendTo(panel);
        self.range.push(date_id);
      }
      else {
        date_container.prependTo(panel);
        self.range.unshift(date_id);
      }
      
      // create date header
      $('<div/>', {'id':date_id+'-header', text:data.date})
      .css('width', width)
      .css('padding-bottom', '15px')
      .css('font-family', "'Fugaz One', cursive")
      .css('font-size', width/10)
      //.css('color', 'yellow')
      //.css('background-color', 'black')
      .css('vertical-align', 'middle')
      .css('text-align', 'center')
      .appendTo('#'+date_id);
      
      // sort topics by weight
      var sorted_topics = Object.keys(data.topics).sort(function(a,b) {
        return data.topics[b].weight - data.topics[a].weight;
      })
    
      // append topics
      $(sorted_topics).each(function (i,t) {
        //var topic_prior = data.topics[t].alpha / topic_total;
        //var topic_height = (panel.height()-header_height) * topic_prior;
        
        $('<div/>', {'text': data.topics[t].words.join(' ')})
        //.css('position', 'absolute')
        //.css('top', top)
        //.css('height', topic_height)
        .css('width', width - 5)
        .css('overflow', 'hidden')
        .css('font-size', Math.log(1+data.topics[t].weight)*(width/100)+width/10)
        .css('font-family', "'Josefin Sans', sans-serif")
        .css('word-spacing', '10%')
        .css('line-height', '120%')
        .css('border-style', 'solid')
        .css('border-width', 2)
        .css('margin', 1)
        .click(function () {
          self.driver.add_context(new CloudTopic(self.driver, self.name, t));
        })
        //.css('border-radius', 15)
        .appendTo('#'+date_id);
      });
      
      // decrement active counter
      self.active--;
    };
    if (offset in self.cache) {
      addOffsetHandler(self.cache[offset]);
    }
    else {
      $.get('/cloud_data/' + self.name + '/' + offset, function (data) {
        self.cache[offset] = data;
        addOffsetHandler(data);
      });
    }
  };
}

function CloudTopic(driver, name, topic) {
  var self = this;
  self.driver = driver;
  self.name = name;
  self.topic = self.nav = topic;
  self.data = [];
  self.range = [];
  self.start = 0;
  self.end = 7;
  self.top = 0;
  
  self.resize = function () {
    var resize_helper = function () {
      for (var i = self.start; i < self.end; ++i) {
        self.addOffset(i, -1);
      }
      $('html, body').animate({ scrollTop: self.top }, 0);
    }
    if (self.data.length == 0) {
      $.get('/cloud_data_topic/' + self.name + '/' + self.topic, function (data) {
        self.data = JSON.parse(data);
        self.center();
        resize_helper();
      });  
    }
    else {
      resize_helper();
    }
  };
  
  self.right = function () {
    if (self.end == self.data.length) return;
    
    var first = self.range.shift();
    $('#'+first).remove();
    self.start++;
    self.end++;
    self.addOffset(self.end - 1, -1);
  };
  
  self.left = function (k) {
    if (self.start == 0) return;
    
    var last = self.range.pop();
    $('#'+last).remove();
    self.start--;
    self.end--;
    self.addOffset(self.start, 0);
  };
  
  self.addOffset = function (offset, pos) {
    var panel = $("#panel");
    var data = self.data[offset];
    var date_id = 'panel-' + data.date;
    var top = 0;
    var width = panel.width() / (self.end - self.start) -1;
    
    // create date container
    var date_container =
      $('<div/>', {'id': date_id})
      .css('float', 'left')
      .css('top', top)
      .css('height', panel.height())
      .css('width', width);
    if (pos == -1) {
      date_container.appendTo(panel);
      self.range.push(date_id);
    }
    else {
      date_container.prependTo(panel);
      self.range.unshift(date_id);
    }
    
    // create date header
    $('<div/>', {'id':date_id+'-header', text:data.date})
    .css('width', width)
    .css('padding-bottom', '15px')
    .css('font-family', "'Fugaz One', cursive")
    .css('font-size', width/10)
    .css('vertical-align', 'middle')
    .css('text-align', 'center')
    .appendTo('#'+date_id);
  
    // append topics
    $(data.topics).each(function (i, t) {
      var td = $('<div/>')
              .css('width', width-5)
              .css('overflow', 'hidden')
              .css('font-size', Math.log(1+t.weight)*(width/100)+width/10)
              .css('font-family', "'Josefin Sans', sans-serif")
              .css('font-weight', t.id == self.topic ? 'bold' : 'normal')
              .css('word-spacing', '10%')
              .css('line-height', '120%')
              .css('border-style', 'solid')
              .css('border-width', 2)
              .append(
                $('<div/>', {'text': t.words.join(' ')})
                .css('border-bottom', 'solid')
                .css('margin', 10)
                .click(function () {
                    self.driver.add_context(new CloudTopic(self.driver, self.name, t.id));
                })
              )
              .appendTo('#'+date_id);
      
      $(t.documents.sort(function (a, b) { return b.weight - a.weight; }).slice(0,4)).each(function (j, d) {
        td.append(
          $('<div/>')
          .css('border-bottom', 'solid')
          .css('margin', 10)
          .append($('<a href="' + d.url + '" target="_blank">' + d.title + '</a>')));
      })
    });
  };
  
  self.center = function () {
    // set the pointers for start and end
    for (var i = 0; i < self.data.length; ++i) {
      if (self.data[i].topics.length > 0 && self.data[i].topics[0].id == self.topic) {
        self.start = i;
        break;
      }
    }
    // try to center around topic in question
    if (self.start + 4 > self.data.length) {
      self.start -= self.start + 4 - self.data.length;
      self.end = self.start + 4;
    }
    else if (self.start - 3 < 0) {
      self.start = 0;
      self.end = 7;
    }
    else {
      self.start = self.start - 3;
      self.end = self.start + 7;
    }
  };
}

function Cloud(name) {
  var self = this;
  self.name = name;
  self.current = [];
  
  self.init = function () {
    $(window).resize(function() {
      if(this.resizeTO) clearTimeout(this.resizeTO);
      this.resizeTO = setTimeout(function() {
        $(this).trigger('resizeEnd');
      }, 500);
    });
    $(window).bind('resizeEnd', function () {
      self.resize();
    });
    $(document).keydown(function (e) {
      if (e.which == 39) self.right();
      if (e.which == 37) self.left();
    });
    $('#panel-left').click(function () {
      self.left();
    });
    $('#panel-right').click(function () {
      self.right();
    });
    
    self.add_context(new CloudAll(self, self.name));
  };
  
  self.add_context = function (c) {
    var txt = (self.current.length == 0 ? ' ' : ' / ') + c.nav;
    var sz = (self.current.length == 0 ? 40 : 30)
    $('<span/>', {text : txt})
    .addClass('fake-link')
    .css('font-size', sz)
    .click(function () {
      self.remove_context(c);
    })
    .appendTo('#panel-top');
    
    self.current.push(c);
    self.resize();
  };
  
  self.remove_context = function (c) {
    while (self.current[self.current.length-1].nav != c.nav) {
      $('#panel-top').children().slice(self.current.length-1).detach();
      self.current.pop();
    }
    self.resize();
  };
  
  self.resize = function () {
    var panel = $("#panel");
    panel.empty();
    panel.css('width', $(window).width() - 195);
    panel.css('height', $(window).width() - 25);
    self.current[self.current.length-1].resize();
  }
  self.left = function () {
    self.current[self.current.length-1].left();
  }
  
  self.right = function () {
    self.current[self.current.length-1].right();
  }

  self.init();
}