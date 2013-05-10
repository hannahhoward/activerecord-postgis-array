# ActiveRecordPostgisArrays

Adds support for missing PostgreSQL data types to ActiveRecord.

[![Build Status](https://secure.travis-ci.org/dockyard/activerecord-postgis-array.png?branch=master)](http://travis-ci.org/dockyard/activerecord-postgis-array)
[![Code Climate](https://codeclimate.com/badge.png)](https://codeclimate.com/github/dockyard/activerecord-postgis-array)

## Looking for help? ##

If it is a bug [please open an issue on
Github](https://github.com/dockyard/party_foul/issues). If you need help using
the gem please ask the question on
[Stack Overflow](http://stackoverflow.com). Be sure to tag the
question with `DockYard` so we can find it.

## Installation

Add this line to your application's Gemfile:

    gem 'activerecord-postgis-array'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install activerecord-postgis-array

## Usage

Just `require 'activerecord-postgis-array'` and use ActiveRecord as you normally would! postgres\_ext extends
ActiveRecord's data type handling.

 * [Migration/Schema.rb support](docs/migrations.md)
 * [Type Casting support](docs/type_casting.md)
 * [Querying PostgreSQL datatypes](docs/querying.md)
 * [Indexes](docs/indexes.md)

## Usage Notes
Avoid the use of in place operators (ie `Array#<<`). These changes are
*not* tracked by Rails ([this issue](https://github.com/rails/rails/issues/6954))
explains why). In place modifications also modify the default object.

Assuming we have the following model:

```ruby
create_table :items do |t|
  t.string :names, :array => true, :default => []
end

class Item < ActiveRecord::Base
end
```

The following will modify the default value of the names attribute.

```ruby
a = Item.new
a.names << 'foo'

b = Item.new
puts b.names
# => ['foo']
```

The supported way of modifying `a.names`:

```ruby
a = Item.new
a.names += ['foo']

b = Item.new
puts b.names
# => []
```

As a result, in place operators are discouraged and will not be
supported in postgres\_ext at this time. 




## Authors

Dan McClain [twitter](http://twitter.com/_danmcclain) [github](http://github.com/danmcclain)

