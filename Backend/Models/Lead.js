import mongoose from "mongoose";

const LeadSchema = new mongoose.Schema({
  source: { type: String, default: 'google_form' },
  rawForm: { type: Object },
  name: { type: String, index: true },
  email: { type: String, index: true },
  phone: { type: String, index: true },
  businessName: { type: String },
  businessCategory: { type: String },
  subCompanyIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'SubCompany' }],
  chosenServices: [
    {
      title: { type: String },
      offerings: [{ type: String }]
    }
  ],

  status: {
    type: String,
    enum: ['new', 'contacted', 'qualified', 'converted', 'lost'],
    default: 'new'
  },
  assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  notes: [
    {
      by: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
      text: String,
      createdAt: Date
    }
  ],
}, { timestamps: true });

const Lead = mongoose.model('Lead', LeadSchema);
export default Lead;
