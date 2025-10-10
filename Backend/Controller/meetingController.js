import mongoose from "mongoose";
import Meeting from "../Models/Meeting.js";
import Lead from "../Models/Lead.js";
import Client from "../Models/Client.js";
import Project from "../Models/Project.js";


export const addMeeting = async (req, res) => {
  try {
    const {
      title,
      agenda,
      project,
      subCompany,
      organizer,
      participants,
      lead,
      client,
      startTime,
      endTime,
      location,
      meetingLink,
      notes,
    } = req.body;

    if (!title) return res.status(400).json({ success: false, message: "Title is required" });
    if (!startTime || !endTime)
      return res.status(400).json({ success: false, message: "Start and End time are required" });

    // Must have either lead or client
    if (!lead && !client)
      return res.status(400).json({
        success: false,
        message: "Meeting must be associated with either a Lead or a Client",
      });

    if (lead) {
      const leadExists = await Lead.findById(lead);
      if (!leadExists)
        return res.status(404).json({ success: false, message: "Lead not found" });
    }

    if (client) {
      const clientExists = await Client.findById(client);
      if (!clientExists)
        return res.status(404).json({ success: false, message: "Client not found" });
    }

    if (project && !mongoose.Types.ObjectId.isValid(project)) {
      return res.status(400).json({ success: false, message: "Invalid project ID" });
    }

    const meeting = await Meeting.create({
      title,
      agenda,
      project,
      subCompany,
      organizer: organizer || req.user?._id,
      participants,
      lead,
      client,
      startTime,
      endTime,
      location,
      meetingLink,
      notes,
    });

    res.status(201).json({
      success: true,
      message: "Meeting added successfully",
      data: meeting,
    });
  } catch (err) {
    console.error("Error adding meeting:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};


export const updateMeeting = async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid meeting ID" });

    const meeting = await Meeting.findById(id);
    if (!meeting)
      return res.status(404).json({ success: false, message: "Meeting not found" });

    // Ensure either lead or client remains linked
    if (updates.lead && updates.client) {
      return res
        .status(400)
        .json({ success: false, message: "Meeting can only be linked to either a lead or a client" });
    }

    // Validate new references if changed
    if (updates.lead) {
      const leadExists = await Lead.findById(updates.lead);
      if (!leadExists)
        return res.status(404).json({ success: false, message: "Lead not found" });
    }

    if (updates.client) {
      const clientExists = await Client.findById(updates.client);
      if (!clientExists)
        return res.status(404).json({ success: false, message: "Client not found" });
    }

    // Apply updates
    Object.assign(meeting, updates);

    await meeting.save();

    res.status(200).json({
      success: true,
      message: "Meeting updated successfully",
      data: meeting,
    });
  } catch (err) {
    console.error("Error updating meeting:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};

export const deleteMeeting = async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid meeting ID" });

    const meeting = await Meeting.findById(id);
    if (!meeting)
      return res.status(404).json({ success: false, message: "Meeting not found" });

    await meeting.deleteOne();

    res.status(200).json({
      success: true,
      message: "Meeting deleted successfully",
    });
  } catch (err) {
    console.error("Error deleting meeting:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};


export const getAllMeetings = async (req, res) => {
  try {
    const { meetingWithType, lead, client, project, subCompany } = req.query;
    const filter = {};

    if (meetingWithType) filter.meetingWithType = meetingWithType;
    if (lead) filter.lead = lead;
    if (client) filter.client = client;
    if (project) filter.project = project;
    if (subCompany) filter.subCompany = subCompany;

    const meetings = await Meeting.find(filter)
      .populate("lead", "name email phone")
      .populate("client", "name email phone")
      .populate("organizer", "fullName email")
      .populate("participants", "fullName email")
      .populate("project", "title")
      .sort({ startTime: 1 });

    res.status(200).json({
      success: true,
      count: meetings.length,
      data: meetings,
    });
  } catch (err) {
    console.error("Error getting meetings:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};


export const getMeetingById = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid meeting ID" });

    const meeting = await Meeting.findById(id)
      .populate("lead", "name email phone")
      .populate("client", "name email phone")
      .populate("organizer", "fullName email")
      .populate("participants", "fullName email")
      .populate("project", "title");

    if (!meeting)
      return res.status(404).json({ success: false, message: "Meeting not found" });

    res.status(200).json({ success: true, data: meeting });
  } catch (err) {
    console.error("Error getting meeting by ID:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};
